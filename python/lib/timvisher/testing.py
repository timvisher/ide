import contextlib
import os
import shutil
import tempfile


@contextlib.contextmanager
def fresh_home():
    root = tempfile.mkdtemp(prefix="fresh_home.")
    home = os.path.join(root, "home")
    try:
        shutil.copytree(os.environ["TIMVISHER_TESTS_TEMPLATE"], home, symlinks=True)
    except BaseException:
        _remove_tree(root)
        raise
    names = {
        "HOME": home,
        "XDG_CONFIG_HOME": os.path.join(home, ".config"),
        "XDG_DATA_HOME": os.path.join(home, ".local", "share"),
        "XDG_STATE_HOME": os.path.join(home, ".local", "state"),
        "XDG_CACHE_HOME": os.path.join(home, ".cache"),
        "TIMVISHER_GIT_HOME": os.path.join(home, "git"),
    }
    saved = {name: os.environ.get(name) for name in names}
    os.environ.update(names)
    try:
        yield home
    finally:
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        _remove_tree(root)


def _remove_tree(root):
    for parent, dirs, files in os.walk(root):
        for name in dirs + files:
            path = os.path.join(parent, name)
            if not os.path.islink(path):
                os.chflags(path, 0)
    shutil.rmtree(root)
