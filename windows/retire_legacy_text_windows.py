"""Stop only the old PC Setup text stack, leaving Colibri image and all files."""
import argparse
import importlib.util
import json
from pathlib import Path
import os


def retire(root: Path):
    import msvcrt
    def safe(path):
        for member in (path,*path.parents):
            try: info=member.lstat()
            except FileNotFoundError: continue
            if member.is_symlink() or getattr(info,'st_file_attributes',0)&0x400:
                raise ValueError(f'Refusing linked old setup path: {member}')
        return path

    module_path=Path(__file__).with_name('openwebui_desktop.py')
    spec=importlib.util.spec_from_file_location('legacy_pc_setup_launcher',module_path)
    legacy=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    state_path=safe(root/'processes.json')
    lock_path=safe(root/'desktop.lock')
    cfg=json.loads(safe(root/'desktop.json').read_text(encoding='utf-8-sig'))
    # Coordinate with the installed shortcuts. Never start a second old runtime.
    with lock_path.open('a+b') as lock:
        lock.seek(0)
        if lock.read(1)==b'':
            lock.write(b'0')
            lock.flush()
        lock.seek(0)
        msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        state=json.loads(state_path.read_text(encoding='utf-8-sig'))
        record=state.get('model')
        if not record or record.get('kind')!='text':
            return
        expected=[cfg['coli_python'],cfg['coli'],'serve','--host','127.0.0.1',
                  '--port','8000','--model',cfg['text_model']]
        def normalize(args):
            return [os.path.normcase(str(x)) if i==0 else x for i,x in enumerate(args)]
        if normalize(record['command']) != normalize(expected):
            raise ValueError('Unrecognized recorded Colibri text process. Nothing was stopped.')
        process=legacy.owned_process(record)
        if process and process.username().casefold()!=legacy.psutil.Process().username().casefold():
            raise ValueError('Old text process belongs to a different Windows account. Nothing was stopped.')
        legacy.stop_record(record)
        del state['model']
        temporary=safe(state_path.with_suffix('.retire.tmp'))
        with temporary.open('x',encoding='utf-8') as out:
            json.dump(state,out)
        temporary.replace(state_path)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    retire(parser.parse_args().root)
