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
        _keep_global_hooks_off(home)
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


# As timvisher_tests does for each suite's HOME: git drops the runner's
# GIT_CONFIG_* hooksPath override for the receiving side of a push to a
# local repo, which then runs the hooks the global config names.
# ~/.gitconfig is read after the XDG config, so it wins. Never write
# through a link into a real file.
def _keep_global_hooks_off(home):
    gitconfig = os.path.join(home, ".gitconfig")
    if os.path.lexists(gitconfig):
        return
    hooks = os.path.join(home, ".local", "state", "timvisher_tests", "hooks")
    os.makedirs(hooks, exist_ok=True)
    with open(gitconfig, "x") as f:
        f.write(f"[core]\n\thooksPath = {hooks}\n")


def _remove_tree(root):
    for parent, dirs, files in os.walk(root):
        for name in dirs + files:
            path = os.path.join(parent, name)
            if not os.path.islink(path):
                os.chflags(path, 0)
    shutil.rmtree(root)
