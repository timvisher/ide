# The Stitch IDE

The definitive collection of host-only tooling for working with Stitch.

Please check out to `~/git/ide`.

## `bash`

`bash` is our shell. We generally have to maintain backwards compatibility
with `bash-3.2` because that's what mac's have and they will likely never
have anything else.

If you want to use `zsh` keep in mind that you may develop habits that are
out of step with prod and with the dev boxes. Prod and the dev boxes will
likely never have `zsh` as the default shell.

You can install or remove this configuration by:

```bash
cd ~/git/ide/bash && ./install.bash
```

```bash
cd ~/git/ide/bash && ./remove.bash
```

### General

#### `backup`

Created a dated backup of a file.

```
Fri Oct 28 09:24:18
tvisher@timvisher-rjmetrics.local
~
$ touch foo

Fri Oct 28 09:25:34
tvisher@timvisher-rjmetrics.local
~
$ ls -la foo*
-rw-r--r--  1 tvisher  staff     0B Oct 28 09:25 foo

Fri Oct 28 09:25:38
tvisher@timvisher-rjmetrics.local
~
$ backup foo

Fri Oct 28 09:25:47
tvisher@timvisher-rjmetrics.local
~
$ ls -la foo*
-rw-r--r--  1 tvisher  staff     0B Oct 28 09:25 foo
-rw-r--r--  1 tvisher  staff     0B Oct 28 09:25 foo.20161028T092547.bak
```

#### `cd`

```
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
```

#### `days_ago`

```
Fri Oct 28 09:24:16
tvisher@timvisher-rjmetrics.local
~
$ days_ago 5
Sun Oct 23 09:24:18 EDT 2016

```

### AWS

#### `ssh_stack_instances`

```
Fri Oct 28 11:55:46
tvisher@timvisher-rjmetrics.local
~
$ ssh_stack_instances primary
ssh '10.0.5.82' # 'dbreplicators-service3'
ssh '10.0.5.50' # 'core-service2'
…
ssh '10.0.5.171' # 'sourcerer-workers10'
```

#### `ssh_matching_instances`

```
Fri Oct 28 12:01:36
tvisher@timvisher-rjmetrics.local
~
$ ssh_matching_instances pipeline dbrepl
ssh '10.0.86.126' # 'dbreplicators-workers1'
ssh '10.0.85.54' # 'dbreplicators-workers2'
ssh '10.0.84.254' # 'dbreplicators-workers3'
ssh '10.0.85.14' # 'dbreplicators-workers4'
ssh '10.0.87.33' # 'dbreplicators-workers5'
ssh '10.0.86.82' # 'dbreplicators-workers6'
```

#### `instance_ips`

```
Fri Oct 28 12:01:40
tvisher@timvisher-rjmetrics.local
~
$ instance_ips
{"Hostname":"admin-staging3","PrivateIp":"10.0.69.12","StackId":"725831b0-00a3-4ed6-bee6-a27de24e95c4","Ec2InstanceId":"i-08b7239b"}
{"Hostname":"admin3","PrivateIp":"10.0.70.5","StackId":"6c75c8a6-6dde-4a44-8c69-018e3aa6d088","Ec2InstanceId":"i-4eef384f"}
{"Hostname":"admin4","PrivateIp":"10.0.71.76","StackId":"6c75c8a6-6dde-4a44-8c69-018e3aa6d088","Ec2InstanceId":"i-1ba02d88"}
{"Hostname":"admin5","PrivateIp":"10.0.71.117","StackId":"6c75c8a6-6dde-4a44-8c69-018e3aa6d088","Ec2InstanceId":"i-12a12c81"}
{"Hostname":"api-staging2","PrivateIp":"10.0.71.22","StackId":"725831b0-00a3-4ed6-bee6-a27de24e95c4","Ec2InstanceId":"i-df4eda4c"}
…
{"Hostname":"webhooks-service9","PrivateIp":"10.0.5.71","StackId":"350219f7-38aa-400e-b872-1ed195cf74e4","Ec2InstanceId":"i-4e3b8edd"}
```

### Clojure

#### `search_clojars`

```
Fri Oct 28 12:03:47
tvisher@timvisher-rjmetrics.local
~
$ search_clojars repl
[tair-repl/tair-repl "1.0.0-SNAPSHOT"] # Tair Repl
[clj-repl/clj-repl "0.1"] # A graphical Clojure REPL
[remote-repl/remote-repl "0.0.1-SNAPSHOT"] # start socket-repl for remote evaluation
…
```

### Stitch

#### `rjmadmin`

```
Fri Oct 28 12:06:35
tvisher@timvisher-rjmetrics.local
~
$ rjmadmin
Welcome to the MySQL monitor.  Commands end with ; or \g.
…
mysql>
```

### `tmux`

`tmux` is our preferred terminal multiplexer.

#### aliases

```
alias t=tmux
alias tl='t ls'
```

#### `nt`/`ntmux`

This allows you to create a standard tmux session for a project.

```
nt [namespace/]project_name [base_dir]
```

`nt` will search for an existing `tmux` session named
`[namespace/]project_name`. If that exists, it attaches to it.

If it doesn't exist and you also passed it a `base_dir` it will create a
new tmux session in that directory.

If you didn't pass it a `base_dir` it will look for a directory that
prefix matches `project_name` (Note, _not_ `[namespace/]/project_name`.
The namespace is stripped.) If it finds one, it will create a `tmux`
session named `[namespace/]/project_name` in the matching directory.

**Note**, if it finds more than one match for `base_dir` it chooses the
first one in bash lexicographic order.

If it can't find a match in the current directory, it will look for every
git project up to 3 levels deep from `$HOME` and attempt to match one of
them. This can take awhile and it's often much faster to just pass a base
directory, but the functionality's there.

### VirtualBox

We use VirtualBox for VMs by default.

`vbox` is an alias for CLI interaction with it.

#### `vbox_matching_uuid`

Find VirtualBox VMs with matching names.

```
Fri Oct 28 09:08:43
tvisher@timvisher-rjmetrics.local
~
$ vbox_matching_uuid boxc
8fb863f9-5b66-46c5-a9cb-f8b9e5b7695b # boxcutter_core_1476144949883_86068
0cbf6ed5-ec95-4d88-9ace-9a1bb58812fa # kitchen-boxcutter-default-rjmetrics-os_default_1477621648011_25989
```
