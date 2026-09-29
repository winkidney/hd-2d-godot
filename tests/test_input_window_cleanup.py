"""No display required: a child in a separate session must not leak."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import input_window_test as window_test
from input_window_test import cleanup_owned, identity


class WindowCleanupTest(unittest.TestCase):
    def test_reused_pid_is_not_signalled(self):
        process=Mock(pid=41)
        process.poll.return_value=0
        reads=0
        sent=[]
        def current_identity(pid):
            nonlocal reads
            reads+=1
            return 100 if reads==1 else (None if sent else 200)
        # The original exits between ownership verification and pidfd binding.
        # The descriptor now belongs to its replacement, which must be left alone.
        with patch.object(window_test,'identity',side_effect=current_identity), \
             patch.object(window_test,'project_processes',return_value=set()), \
             patch.object(window_test,'children',return_value=set()), \
             patch.object(window_test.os,'pidfd_open',return_value=1041,create=True), \
             patch.object(window_test.signal,'pidfd_send_signal',side_effect=lambda fd,sig,*args:sent.append((fd,sig)),create=True), \
             patch.object(window_test.os,'kill',side_effect=lambda pid,sig:sent.append((pid,sig))), \
             patch.object(window_test.os,'close'):
            cleanup_owned(process,Path('/isolated/project'),{41:100})
        self.assertEqual(sent,[],'Cleanup signalled a replacement process')

    def test_late_project_child_is_cleaned(self):
        process=Mock(pid=41)
        process.poll.return_value=0
        live={41:100,42:200}
        sent=[]
        def stop(pid,sig):
            sent.append(pid)
            live.pop(pid,None)
        # Child 42 appears in the project scan only after its parent has exited.
        with patch.object(window_test,'identity',side_effect=live.get), \
             patch.object(window_test,'project_processes',side_effect=lambda _project:{42} if 41 not in live and 42 in live else set()), \
             patch.object(window_test,'children',return_value=set()), \
             patch.object(window_test.os,'pidfd_open',side_effect=lambda pid,*args:pid+1000,create=True), \
             patch.object(window_test.signal,'pidfd_send_signal',side_effect=lambda fd,sig,*args:stop(fd-1000,sig),create=True), \
             patch.object(window_test.os,'kill',side_effect=stop), \
             patch.object(window_test.os,'close'):
            result=cleanup_owned(process,Path('/isolated/project'),{41:100})
        self.assertTrue(result['passed'],result)
        self.assertEqual(set(sent),{41,42})

    def test_separate_session_child_and_unrelated_process(self):
        unrelated=subprocess.Popen([sys.executable,'-c','import time;time.sleep(120)'],start_new_session=True)
        code='import subprocess,sys,time;child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(120)"],start_new_session=True);print(child.pid,flush=True);time.sleep(120)'
        parent=subprocess.Popen([sys.executable,'-c',code],stdout=subprocess.PIPE,text=True,start_new_session=True)
        child=int(parent.stdout.readline().strip())
        try:
            self.assertNotEqual(os.getpgid(parent.pid),os.getpgid(child))
            with tempfile.TemporaryDirectory(prefix='hd2d-cleanup-') as folder:
                result=cleanup_owned(parent,Path(folder),{child})
            self.assertTrue(result['passed'],result)
            self.assertIsNone(identity(child))
            self.assertIsNone(identity(parent.pid))
            self.assertIsNone(unrelated.poll(),'Cleanup touched an unrelated process')
        finally:
            for pid in (child,parent.pid,unrelated.pid):
                if identity(pid) is not None:
                    try:os.kill(pid,15)
                    except ProcessLookupError:pass
            parent.wait(timeout=5);unrelated.wait(timeout=5)
            parent.stdout.close()

    def test_already_exited_parent(self):
        parent=subprocess.Popen([sys.executable,'-c','pass'])
        parent.wait(timeout=5)
        with tempfile.TemporaryDirectory(prefix='hd2d-cleanup-') as folder:
            self.assertTrue(cleanup_owned(parent,Path(folder))['passed'])


if __name__=='__main__':unittest.main()
