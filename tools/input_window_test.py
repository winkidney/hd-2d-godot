#!/usr/bin/env python3
"""Real X11 window-input regression. Isolated source/config; only owned windows.

Requires already-installed libX11 and a graphical session. No packages,
global editor settings, or production preferences are changed. GPU jobs serial.
The editor's private debugger listener is intentionally exercised, not mocked.
"""
from pathlib import Path
import argparse
import ctypes as c
import json
import os
import shutil
import signal
import subprocess
import time

from project import ROOT, desktop_environment, engine
from source_files import source_files
from feature_fingerprint import fingerprint

SCENES = ('waystation', 'reference_scene', 'reference_scene_graybox', 'frontal_canal')

class WindowAttributes(c.Structure):
    _fields_=[('x',c.c_int),('y',c.c_int),('width',c.c_int),('height',c.c_int),('border_width',c.c_int),('depth',c.c_int),('visual',c.c_void_p),('root',c.c_ulong),('window_class',c.c_int),('bit_gravity',c.c_int),('win_gravity',c.c_int),('backing_store',c.c_int),('backing_planes',c.c_ulong),('backing_pixel',c.c_ulong),('save_under',c.c_int),('colormap',c.c_ulong),('map_installed',c.c_int),('map_state',c.c_int),('all_event_masks',c.c_long),('your_event_mask',c.c_long),('do_not_propagate_mask',c.c_long),('override_redirect',c.c_int),('screen',c.c_void_p)]

class WindowInputEvent(c.Structure):
    # XKeyEvent and XButtonEvent have the same layout, differing only in detail.
    _fields_=[('type',c.c_int),('serial',c.c_ulong),('send_event',c.c_int),('display',c.c_void_p),('window',c.c_ulong),('root',c.c_ulong),('subwindow',c.c_ulong),('time',c.c_ulong),('x',c.c_int),('y',c.c_int),('x_root',c.c_int),('y_root',c.c_int),('state',c.c_uint),('detail',c.c_uint),('same_screen',c.c_int)]

class XEvent(c.Union):
    _fields_=[('type',c.c_int),('input',WindowInputEvent),('padding',c.c_long*24)]


class NativeInput:
    def __init__(self, env):
        self.x = c.CDLL('libX11.so.6')
        D, W = c.c_void_p, c.c_ulong
        signatures = {
            'XOpenDisplay': ([c.c_char_p], D), 'XDefaultRootWindow': ([D], W),
            'XQueryTree': ([D,W,c.POINTER(W),c.POINTER(W),c.POINTER(c.POINTER(W)),c.POINTER(c.c_uint)],c.c_int),
            'XInternAtom': ([D,c.c_char_p,c.c_int],W),
            'XGetWindowProperty': ([D,W,W,c.c_long,c.c_long,c.c_int,W,c.POINTER(W),c.POINTER(c.c_int),c.POINTER(W),c.POINTER(W),c.POINTER(c.POINTER(c.c_ubyte))],c.c_int),
            'XFree': ([c.c_void_p],c.c_int),
            'XStringToKeysym': ([c.c_char_p],W), 'XKeysymToKeycode': ([D,W],c.c_uint),
            'XSync': ([D,c.c_int],c.c_int),
            'XGetGeometry': ([D,W,c.POINTER(W),c.POINTER(c.c_int),c.POINTER(c.c_int),c.POINTER(c.c_uint),c.POINTER(c.c_uint),c.POINTER(c.c_uint),c.POINTER(c.c_uint)],c.c_int),
            'XTranslateCoordinates': ([D,W,W,c.c_int,c.c_int,c.POINTER(c.c_int),c.POINTER(c.c_int),c.POINTER(W)],c.c_int),
            'XCloseDisplay': ([D],c.c_int),
            'XGetWindowAttributes': ([D,W,c.POINTER(WindowAttributes)],c.c_int),
            'XSendEvent': ([D,W,c.c_int,c.c_long,c.POINTER(XEvent)],c.c_int),
        }
        for name,(args,result) in signatures.items():
            getattr(self.x,name).argtypes=args
            getattr(self.x,name).restype=result
        self.display=self.x.XOpenDisplay(env['DISPLAY'].encode())
        if not self.display: raise RuntimeError('X11 display unavailable')
        # Windows can disappear during enumeration. Do not let libX11 exit Python;
        # ownership/focus assertions still reject invalid targets.
        self.error_callback=c.CFUNCTYPE(c.c_int,D,c.c_void_p)(lambda _display,_event:0)
        self.x.XSetErrorHandler.argtypes=[type(self.error_callback)]
        self.x.XSetErrorHandler(self.error_callback)
        self.root=self.x.XDefaultRootWindow(self.display)
        self.pid_atom=self.x.XInternAtom(self.display,b'_NET_WM_PID',False)

    def children(self, window):
        root=c.c_ulong();parent=c.c_ulong();items=c.POINTER(c.c_ulong)();count=c.c_uint()
        if not self.x.XQueryTree(self.display,window,c.byref(root),c.byref(parent),c.byref(items),c.byref(count)): return []
        result=[int(items[i]) for i in range(count.value)]
        if items:self.x.XFree(items)
        return result

    def owner(self, window):
        actual=c.c_ulong();fmt=c.c_int();count=c.c_ulong();remaining=c.c_ulong();data=c.POINTER(c.c_ubyte)()
        result=self.x.XGetWindowProperty(self.display,window,self.pid_atom,0,1,False,6,c.byref(actual),c.byref(fmt),c.byref(count),c.byref(remaining),c.byref(data))
        pid=int(c.cast(data,c.POINTER(c.c_ulong))[0]) if result==0 and count.value and fmt.value==32 else 0
        if data:self.x.XFree(data)
        return pid

    def windows(self, pids):
        queue=self.children(self.root);found=[]
        while queue:
            window=queue.pop()
            attributes=WindowAttributes()
            mapped=self.x.XGetWindowAttributes(self.display,window,c.byref(attributes)) and attributes.map_state==2
            if mapped and attributes.width>100 and attributes.height>100 and self.owner(window) in pids:found.append((attributes.width*attributes.height,window))
            queue.extend(self.children(window))
        return [window for _area,window in sorted(found,reverse=True)]

    def focus(self, window, pids):
        if self.owner(window) not in pids:raise RuntimeError('Refuse unrelated window')
        # Never raise a window, warp the desktop pointer, or steal keyboard focus.
        # The user may keep typing/clicking elsewhere during this test.

    def key(self, window, pids, name, modifier=None):
        self.focus(window,pids)
        code=self.x.XKeysymToKeycode(self.display,self.x.XStringToKeysym(name.encode()))
        if not code:raise RuntimeError('Unknown native key '+name)
        state={None:0,'Shift_L':1,'Control_L':4,'Alt_L':8,'Super_L':64}[modifier]
        for down in (True,False):
            event=XEvent()
            event.input=WindowInputEvent(2 if down else 3,0,True,self.display,window,self.root,0,0,1,1,0,0,state,code,True)
            if not self.x.XSendEvent(self.display,window,False,1 if down else 2,c.byref(event)):raise RuntimeError('Native key delivery failed')
            self.x.XSync(self.display,False)
            time.sleep(.1)
        time.sleep(.12)

    def click(self, window, pids, point, viewport):
        self.focus(window,pids)
        root=c.c_ulong();x=c.c_int();y=c.c_int();width=c.c_uint();height=c.c_uint();border=c.c_uint();depth=c.c_uint()
        if not self.x.XGetGeometry(self.display,window,c.byref(root),c.byref(x),c.byref(y),c.byref(width),c.byref(height),c.byref(border),c.byref(depth)):raise RuntimeError('Window geometry missing')
        screen_x=c.c_int();screen_y=c.c_int();child=c.c_ulong()
        self.x.XTranslateCoordinates(self.display,window,self.root,0,0,c.byref(screen_x),c.byref(screen_y),c.byref(child))
        px=screen_x.value+round(point[0]*width.value/viewport[0])
        py=screen_y.value+round(point[1]*height.value/viewport[1])
        local_x=round(point[0]*width.value/viewport[0]);local_y=round(point[1]*height.value/viewport[1])
        # Deliver only to this owned window, not the desktop's current pointer
        # target. Key/button events still traverse the native Window input path.
        for down in (True,False):
            event=XEvent()
            event.input=WindowInputEvent(4 if down else 5,0,True,self.display,window,self.root,0,0,local_x,local_y,px,py,0 if down else 256,1,True)
            if not self.x.XSendEvent(self.display,window,False,4 if down else 8,c.byref(event)):raise RuntimeError('Native click delivery failed')
            self.x.XSync(self.display,False);time.sleep(.1)
        time.sleep(.2)

    def close(self):
        self.x.XCloseDisplay(self.display)


def children(pid):
    result=set()
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            tail=path.read_text().rsplit(')',1)[1].split()
            if int(tail[1])==pid:result.add(int(path.parent.name))
        except (OSError,ValueError,IndexError):pass
    return result


def alive(pid):
    try:return Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[0]!='Z'
    except OSError:return False

def identity(pid):
    try:
        fields=Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()
        return int(fields[19]) if fields[0]!='Z' else None
    except (OSError,ValueError,IndexError):return None


def project_processes(project):
    """Find orphaned Godot children by the exact isolated --path argument."""
    found=set()
    for path in Path('/proc').glob('[0-9]*/comm'):
        try:
            if not path.read_text().strip().lower().startswith('godot'):continue
            args=(path.parent/'cmdline').read_bytes().split(b'\0')
            for index,arg in enumerate(args[:-1]):
                if arg==b'--path' and args[index+1]==os.fsencode(project):
                    found.add(int(path.parent.name))
                    break
        except (OSError,ValueError):pass
    return found


def cleanup_owned(process, project, known=()):
    """Stop all owned descendants, even if Godot gave them separate sessions.

    Keep the first observed start time and signal only a matching bound pidfd.
    Rescan the exact isolated project while stopping late/reparented children.
    """
    identities=dict(known) if isinstance(known,dict) else {pid:identity(pid) for pid in known}
    if process.poll() is None:identities.setdefault(process.pid,identity(process.pid))
    identities={pid:start for pid,start in identities.items() if start is not None}
    handles={};errors=set()
    def remaining():return [pid for pid,start in identities.items() if identity(pid)==start]
    def discover():
        for pid in project_processes(project):
            start=identity(pid)
            if start is not None:identities.setdefault(pid,start)
        queue=remaining();visited=set()
        while queue:
            parent=queue.pop()
            if parent in visited or identity(parent)!=identities[parent]:continue
            visited.add(parent)
            descendants=children(parent)
            if identity(parent)!=identities[parent]:continue
            for child in descendants:
                start=identity(child)
                if start is not None:
                    identities.setdefault(child,start)
                    if child not in visited and identities[child]==start:queue.append(child)
    try:
        discover()
        supported=callable(getattr(os,'pidfd_open',None)) and callable(getattr(signal,'pidfd_send_signal',None))
        if not supported:errors.add('pidfd cleanup unavailable; no signals sent. Use /usr/bin/python3.')
        else:
            quiet=False
            for sig,seconds in ((signal.SIGTERM,3),(signal.SIGKILL,3)):
                deadline=time.monotonic()+seconds;quiet_since=None;sent=set()
                while True:
                    discover()
                    for pid in remaining():
                        if pid in sent:continue
                        try:
                            if pid not in handles:
                                fd=os.pidfd_open(pid,0)
                                # Binding may race with exit/reuse. Never replace the
                                # original identity with the newly observed process.
                                if identity(pid)!=identities[pid]:
                                    os.close(fd)
                                    continue
                                handles[pid]=fd
                            signal.pidfd_send_signal(handles[pid],sig,None,0)
                            sent.add(pid)
                        except ProcessLookupError:pass
                        except (OSError,NotImplementedError) as exc:
                            errors.add(f'pidfd cleanup failed for {pid}: {exc}')
                    now=time.monotonic()
                    if remaining():quiet_since=None
                    elif quiet_since is None:quiet_since=now
                    elif now-quiet_since>=.2:
                        quiet=True
                        break
                    if now>=deadline:break
                    time.sleep(.05)
                if quiet:break
        try:process.wait(timeout=2)
        except subprocess.TimeoutExpired:pass
        leaked=sorted(set(remaining())|project_processes(project))
        return {'passed':not leaked and not errors,'tracked_pids':sorted(identities),'remaining_pids':leaked,'errors':sorted(errors)}
    finally:
        for fd in handles.values():os.close(fd)


def require_pidfd():
    """Refuse graphical startup when this interpreter cannot clean up safely."""
    if not callable(getattr(os,'pidfd_open',None)) or not callable(getattr(signal,'pidfd_send_signal',None)):
        raise SystemExit('Safe window cleanup requires pidfd APIs. Run with /usr/bin/python3; no installation is needed.')
    fd=None
    try:
        fd=os.pidfd_open(os.getpid(),0)
        signal.pidfd_send_signal(fd,0,None,0)
    except (OSError,NotImplementedError) as exc:
        raise SystemExit(f'pidfd cleanup preflight failed; no windows opened: {exc}') from exc
    finally:
        if fd is not None:os.close(fd)


def wait_for(test, seconds=30):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        value=test()
        if value:return value
        time.sleep(.08)
    raise RuntimeError('Timed out waiting for test state')


def read_state(folder):
    try:return json.loads((folder/'state.json').read_text())
    except (OSError,json.JSONDecodeError):return {}


def run_case(project, out, env, native, mode, scene):
    folder=out/(mode+'-'+scene);folder.mkdir()
    case_env=env|{'HD2D_INPUT_PROBE_OUT':str(folder)}
    command=[engine(),'--path',str(project),'--display-driver','x11','--audio-driver','Dummy','--resolution','1280x720','--position','40,40','--max-fps','60']
    command+=(['--editor'] if mode=='editor' else [])+['res://scenes/'+scene+'.tscn']
    command+=['--','--ignore-user-settings']
    checks=[];result={'mode':mode,'scene':scene,'checks':checks,'passed':False}
    def check(ok,label):
        checks.append({'name':label,'passed':bool(ok)})
        if not ok:raise AssertionError(label)
    with (folder/'engine.log').open('w') as log:
        tracked={}
        process=subprocess.Popen(command,env=case_env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            pids={process.pid}
            tracked[process.pid]=identity(process.pid)
            result['stage']='launcher window'
            own={process.pid};window=wait_for(lambda:native.windows(own))[0]
            if mode=='editor':
                time.sleep(9)
                window=wait_for(lambda:native.windows(own))[0]
                result['stage']='editor F6 -> child process'
                native.key(window,own,'F6')
                pids=wait_for(lambda:children(process.pid))
                tracked.update({pid:identity(pid) for pid in pids})
                result['stage']='child game window'
                window=wait_for(lambda:native.windows(pids))[0]
            else:pids=own
            result['stage']='scene ready state'
            wait_for(lambda:read_state(folder).get('ticks',0)>20)
            time.sleep(.5)
            def state():return read_state(folder)
            def press(key,modifier=None):
                check(any(alive(p) for p in pids),'alive before '+key)
                previous=state().get('ticks',0)
                native.key(window,pids,key,modifier)
                delivered=state().get('ticks',previous)
                wait_for(lambda:state().get('ticks',0)>delivered+5,5)
                check(any(alive(p) for p in pids),'alive after '+key)
                return state()
            sequence=0
            def control(action,**extra):
                nonlocal sequence
                sequence+=1
                temp=folder/'command.tmp'
                temp.write_text(json.dumps({'id':sequence,'action':action}|extra))
                temp.replace(folder/'command.json')
                wait_for(lambda:state().get('command_id',0)>=sequence and not state().get('capture_pending',False))
                return state()
            check(press('p')['parallax'],'P opens parallax through native window')
            check(not press('p')['parallax'],'P closes once')
            check(press('o')['dof_panel'],'O opens DOF')
            s=press('p');check(s['parallax'] and not s['dof_panel'],'P/O exclusive')
            control('capture',name='parallax.png')
            for mod in ('Control_L','Shift_L','Alt_L'):
                s=press('p',mod);check(s['parallax'],'modified P does not toggle '+mod)
            s=control('focus_spin');check(s['focus_type'].endswith('LineEdit'),'real parallax SpinBox focus')
            focus=s['focus'];preset=s['time']
            s=press('Tab');check(s['hud'] and s['parallax'] and s['focus']!=focus,'Tab navigates without hiding UI')
            control('focus_spin')
            for key in ('1','2','3','t','h','p','o','c','g','b','k'):
                s=press(key)
                check(s['hud'] and s['parallax'] and s['time']==preset and not s['tour'],'text focus contains '+key)
            control('release_focus');s=press('Escape')
            check(not s['parallax'] and not s['quit_dialog'],'Esc closes panel without quitting')
            for key,field in (('g','tour'),('v','effects'),('f','follow'),('b','dof'),('k','background'),('h','hud')):
                initial=state()[field];check(press(key)[field]!=initial,key+' toggles '+field)
                check(press(key)[field]==initial,key+' restores '+field)
            initial=state()['time'];check(press('t')['time']!=initial,'T changes time')
            for key,value in (('1','dusk'),('2','night'),('3','day')):check(press(key)['time']==value,key+' selects '+value)
            camera=state()['camera_supported'];s=press('c')
            check(s['camera']==camera,'C opens camera only on supported scenes')
            if camera:
                control('capture',name='camera.png')
                check(not press('c')['camera'],'C closes camera')
            for button,field in (('dof','dof_panel'),('parallax','parallax'),('camera','camera')):
                if button=='camera' and not camera:continue
                s=state();check(button in s['buttons'],'toolbar '+button+' available')
                native.click(window,pids,s['buttons'][button],s['viewport'])
                wait_for(lambda:state().get(field,False),3)
                check(state()[field],'native mouse opens '+button)
                control('release_focus');press('Escape')
            s=state();native.click(window,pids,s['buttons']['quit'],s['viewport'])
            wait_for(lambda:state()['quit_dialog'])
            check(any(alive(p) for p in pids),'Exit toolbar requires confirmation')
            # Embedded popup belongs to the same root window and gets first refusal.
            check(not press('Escape')['quit_dialog'],'Esc cancels confirmation')
            check(press('Escape')['quit_dialog'],'bare Esc asks instead of exiting')
            check(not press('Return')['quit_dialog'],'default Enter keeps playing')
            check(press('Escape')['quit_dialog'],'Esc opens confirmation again')
            check(not press('Escape')['quit_dialog'],'second Esc cancels instead of exiting')
            control('capture',name='controls.png')
            result['passed']=True
        except Exception as exc:
            result['error']=str(exc);result['last_state']=read_state(folder)
        finally:
            result['cleanup']=cleanup_owned(process,project,tracked)
            if not result['cleanup']['passed']:
                result['passed']=False;result['error']='Owned test processes remained after cleanup'
            (folder/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    output=(folder/'engine.log').read_text()
    if 'SCRIPT ERROR:' in output or 'Parse Error:' in output:
        result['passed']=False;result['error']='Godot script error; see engine.log'
    (folder/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'mode':mode,'scene':scene,'passed':result['passed'],'checks':len(checks),'error':result.get('error')}),flush=True)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=['standalone','editor','both'],default='both')
    parser.add_argument('--scene',choices=SCENES,action='append')
    parser.add_argument('--headless',action='store_true',help='Run four-scene input dispatch in an isolated source and preference copy, without a desktop')
    args=parser.parse_args()
    if not args.headless:require_pidfd()
    out=ROOT/'build/input-window'/time.strftime('%Y%m%d-%H%M%S')
    out.mkdir(parents=True,exist_ok=False)
    before=fingerprint(ROOT)['sha256']
    project=out/'project';project.mkdir()
    for path in source_files(ROOT):
        relative=path.relative_to(ROOT)
        if 'research' in relative.parts:continue
        target=project/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    cfg=project/'project.godot'
    cfg.write_text(cfg.read_text()+'\n[autoload]\n\nInputWindowProbe="*res://tests/input/window_probe.gd"\n')
    env=os.environ.copy() if args.headless else desktop_environment()
    for variable,name in [('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
        env[variable]=str(out/name)
    imported=subprocess.run([engine(),'--headless','--path',str(project),'--editor','--import'],env=env,capture_output=True,text=True,timeout=180)
    (out/'import.log').write_text(imported.stdout+imported.stderr)
    if imported.returncode or 'SCRIPT ERROR:' in imported.stdout+imported.stderr:raise RuntimeError('Import failed; '+str(out/'import.log'))
    if args.headless:
        command=[engine(),'--headless','--path',str(project),'--script','res://tests/input_dispatch.gd','--','--ignore-user-settings','--input-output='+str(out/'dispatch-report.json')]
        result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=180)
        (out/'dispatch.log').write_text(result.stdout+result.stderr)
        report=json.loads((out/'dispatch-report.json').read_text())
        ok=result.returncode==0 and report.get('passed',False) and before==fingerprint(ROOT)['sha256'] and 'SCRIPT ERROR:' not in result.stdout+result.stderr
        print(result.stdout[-3000:]+result.stderr[-3000:])
        print('Report: '+str(out/'dispatch-report.json'))
        raise SystemExit(0 if ok else 1)
    native=NativeInput(env)
    try:
        cases=[run_case(project,out,env,native,mode,scene) for mode in (['standalone','editor'] if args.mode=='both' else [args.mode]) for scene in (args.scene or SCENES)]
    finally:native.close()
    after=fingerprint(ROOT)['sha256']
    report={'passed':all(case['passed'] for case in cases) and before==after,'runtime_fingerprint':before,'fingerprint_unchanged':before==after,'native_input':'Targeted XSendEvent into owned X11 windows, through Godot Window input and GUI; no pointer warping or focus stealing; isolated editor/user settings. Synthetic native events, not physical hardware input.','cases':cases}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Report: '+str(out/'report.json'),flush=True)
    raise SystemExit(0 if report['passed'] else 1)


if __name__=='__main__':main()
