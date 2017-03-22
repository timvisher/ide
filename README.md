# The Stitch IDE

The definitive collection of tooling that should work on your host for
working with Stitch.

Please check out to `~/git/ide`.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Installation](#installation)
- [`bash`](#bash)
  - [Installation](#installation-1)
  - [General](#general)
    - [`backup`](#backup)
    - [`cd`](#cd)
    - [`days_ago`](#days_ago)
  - [AWS](#aws)
    - [`assume_*`](#assume_)
    - [`multi_exec*`](#multi_exec)
    - [`layer_instance_exec`](#layer_instance_exec)
    - [`set_default_profile`](#set_default_profile)
    - [`ssh_layer_instances`](#ssh_layer_instances)
    - [`ssh_matching_instances`](#ssh_matching_instances)
    - [`ssh_stack_instances`](#ssh_stack_instances)
    - [`ssh_*_instances`](#ssh__instances)
    - [`ssh_instance`](#ssh_instance)
    - [`delete_known_host_line`](#delete_known_host_line)
  - [Editing environments](#editing-environments)
    - [`edit_frontend_envs_[start|end]`](#edit_frontend_envs_startend)
  - [Clojure](#clojure)
    - [`search_clojars`](#search_clojars)
  - [Stitch](#stitch)
    - [`rjmadmin`](#rjmadmin)
  - [`tmux`](#tmux)
    - [aliases](#aliases)
    - [`nt`/`ntmux`](#ntntmux)
  - [VirtualBox](#virtualbox)
    - [`vbox_matching_uuid`](#vbox_matching_uuid)
- [emacs](#emacs)
  - [Installation](#installation-2)
  - [General Notes](#general-notes)
  - [Active repositories](#active-repositories)
  - [Selected Packages](#selected-packages)
  - [`M-x header-comment`](#m-x-header-comment)
  - [`C-c C`/`M-x rjmetrics-dired-code-dir`](#c-c-cm-x-rjmetrics-dired-code-dir)
  - [`M-x rjmetrics-clone-repo`](#m-x-rjmetrics-clone-repo)
  - [`<f5>`/`M-x todo-frame-bounce`](#f5m-x-todo-frame-bounce)
  - [`M-x github-source-link`](#m-x-github-source-link)
  - [`M-x github-commit-link`](#m-x-github-commit-link)
  - [`M-x github-compare`](#m-x-github-compare)
  - [`M-x github-add-my-public`](#m-x-github-add-my-public)
  - [`M-Q`/`M-x unfill-paragraph`](#m-qm-x-unfill-paragraph)
- [`ssh`](#ssh)
- [Rationale](#rationale)
- [Compatibility](#compatibility)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Installation

Installation will be specific to most of the sections written below here.
See the 'Installation' section of the tool you're interested in for more
details.

As a general note though, be aware that updates to this repo will have to
be refreshed into whatever running environments you already have open. For
instance, bash will have to `source ~/.bashrc` to fully refresh the bash
configuration. Even then, if there was a breaking change like the rename
of a function your running shell will still have the old stuff present.
You'll need to develop a bit of situational awareness to decide how best
to get updates for a given tool.

## `bash`

`bash` is our shell. We generally have to maintain backwards compatibility
with `bash-3.2` because that's what mac's have and they will likely never
have anything else.

If you want to use `zsh` keep in mind that you may develop habits that are
out of step with prod and with the dev boxes. Prod and the dev boxes will
likely never have `zsh` as the default shell.

### Installation

You can install or remove this configuration by:

```bash
cd ~/git/ide/bash && ./install.bash
```

```bash
cd ~/git/ide/bash && ./remove.bash
```

**NOTE:** An enormous amount of our functionality requires `jq` to be
installed.

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

To get started, set up your `default` profile using `aws --profile default
configure` and your AWS provided key pair and then run
`configure_aws_profiles`.

`configure_aws_profiles` will set up the following profiles:

- `read_only`
- `poweruser`
- `admin_global`

You can then use them either by `set_default_profile` or by `assume_*`.

#### `assume_*`

If you need to assume an AWS role for a tool other than the aws cli you'll
need to export the proper environment variables.

You can initialize a shell with a new role using one of the `assume_*`
convenience aliases.

```
Mon Oct 31 13:42:43
tvisher@timvisher-rjmetrics.local
~/git/ide
$ assume_read_only 484610

Mon Oct 31 13:42:58
tvisher@timvisher-rjmetrics.local
[read_only:59m]
~/git/ide
$
```

The `assume_*` aliases are also available in compact forms like `aag` for
`Assume_Admin_Global` or `aro` for `Assume_Read_Only` etc.

If you've assumed a role and it still hasn't expired you can export it
into another shell using `export_aws_vars` or just run the corresponding
`assume_*` command which will read from the cache if it exists and has not
expired.

```
Mon Oct 31 13:51:52
tvisher@timvisher-rjmetrics.local
~/git/ide
$ export_aws_vars

Mon Oct 31 13:51:56
tvisher@timvisher-rjmetrics.local
[read_only:51m]
~/git/ide
$
```

To see your currently cached roles and when they're good till you can run
`pp_role_caches`.

```
Tue Nov 01 11:24:48
tvisher@timvisher-rjmetrics.local
[admin_global:41m]
~/git/ide
$ pp_role_caches
assume_read_only 123456 # 41m
assume_admin_global 123456 # 39m
```

Variables take precedence over the default profile.

To see the currently cached role you can use `pp_role_cache`.

In the event that you need to uncache a role because it's about to expire
you think you'll need more time, run `uncache_*` (like
`uncache_admin_global`).

#### `multi_exec*`

You can run a command on multiple OpsWorks instances using the following
commands:

```
Mon Nov 28 10:36:25
tvisher@timvisher-rjmetrics.local
[read_only:26m]
~
$ layer_instances pipeline kafka | jq -r '.Instances[] | .Hostname'
kafka4
kafka3
kafka2
kafka1
kafka5

Mon Nov 28 10:42:52
tvisher@timvisher-rjmetrics.local
[read_only:20m]
~
$ multi_exec_layer pipeline kafka --force date
# Running `date` on the kafka layer:
# kafka4
# kafka3
# kafka2
# kafka1
# kafka5
kafka2
Mon Nov 28 15:44:02 UTC 2016
kafka3
Mon Nov 28 15:44:02 UTC 2016
kafka4
Mon Nov 28 15:44:02 UTC 2016
kafka1
Mon Nov 28 15:44:02 UTC 2016
kafka5
Mon Nov 28 15:44:02 UTC 2016

Mon Nov 28 10:44:02
tvisher@timvisher-rjmetrics.local
[read_only:18m]
~
$ multi_exec pipeline 'kafka[124]' --force date
# Running `date` on the following hosts?
# kafka4
# kafka2
# kafka1
kafka2
Mon Nov 28 15:44:18 UTC 2016
kafka4
Mon Nov 28 15:44:18 UTC 2016
kafka1
Mon Nov 28 15:44:18 UTC 2016
```

`multi_exec_global` and `multi_exec_stack` are also provided and do what
you would expect them to.

There are oodles of convenience aliases defined for you as well:

```
Fri Mar 10 15:28:13
tvisher@timvisher-rjmetrics.local
[read_only:60m]
~/git/ide (master *%>)
$ multi_exec_sourcerer_workers --force uptime
# Running `uptime` on the sourcerer_workers layer:
# sourcerer-workers9
# sourcerer-workers10
# sourcerer-workers2
# sourcerer-workers3
# sourcerer-workers4
# sourcerer-workers11
# sourcerer-workers1
# sourcerer-workers5
# sourcerer-workers6
sourcerer-workers10
 20:28:18 up 2 days, 22:36,  0 users,  load average: 0.01, 0.03, 0.05
sourcerer-workers2
 20:28:18 up 2 days,  6:05,  0 users,  load average: 0.01, 0.03, 0.05
sourcerer-workers9
 20:28:18 up 2 days, 22:36,  0 users,  load average: 0.00, 0.01, 0.05
sourcerer-workers3
 20:28:18 up 2 days,  6:04,  0 users,  load average: 0.21, 0.13, 0.09
sourcerer-workers11
 20:28:19 up  4:37,  0 users,  load average: 0.00, 0.01, 0.05
sourcerer-workers4
 20:28:19 up 2 days,  6:05,  0 users,  load average: 0.02, 0.04, 0.05
sourcerer-workers5
 20:28:19 up  3:42,  1 user,  load average: 0.42, 0.52, 0.56
sourcerer-workers1
 20:28:19 up  3:41,  0 users,  load average: 0.41, 0.39, 0.41
sourcerer-workers6
 20:28:19 up  3:41,  1 user,  load average: 0.50, 0.52, 0.50

Fri Mar 10 15:28:19
tvisher@timvisher-rjmetrics.local
[read_only:59m]
~/git/ide (master *%>)
$ multi_exec_menagerie --force uptime
# Running `uptime` on the menagerie layer:
# menagerie3
# menagerie4
menagerie4
 20:28:37 up 50 min,  0 users,  load average: 0.04, 0.03, 0.05
menagerie3
 20:28:37 up 50 min,  0 users,  load average: 0.05, 0.04, 0.05
```

#### `layer_instance_exec`

Selects an instance from a layer and execs a command on it, possibly
non-interactively.

```
Tue Dec 06 10:32:38
tvisher@timvisher-rjmetrics.local
[read_only:48m]
~/git/cloudcutter (master *$=)
$ layer_instance_exec pipeline kafka date
# Run `date` on kafka1? [y/N] y
kafka1
Tue Dec  6 15:39:44 UTC 2016

Tue Dec 06 10:39:44
tvisher@timvisher-rjmetrics.local
[read_only:41m]
~/git/cloudcutter (master *$=)
$ layer_instance_exec pipeline kafka --force date
# Running `date` on kafka1
kafka1
Tue Dec  6 15:39:50 UTC 2016
```

#### `set_default_profile`

The aws cli is capable of handling MFA etc for you if you export the
default profile or use `--profile` arguments properly.

See
[their docs](http://docs.aws.amazon.com/cli/latest/userguide/cli-roles.html)
for more details.

```
Fri Oct 28 16:31:26
tvisher@timvisher-rjmetrics.local
~
$ set_default_profile read_only

Fri Oct 28 16:31:34
tvisher@timvisher-rjmetrics.local
[default profile: read_only]
~
$
```

Use `unassume_role` to unset your default role.

#### `ssh_layer_instances`

```
Mon Nov 28 10:37:34
tvisher@timvisher-rjmetrics.local
[read_only:25m]
~
$ ssh_layer_instances pipeline kafka
ssh '10.2.83.142' # 'kafka4'
ssh '10.2.86.58' # 'kafka3'
ssh '10.2.79.194' # 'kafka2'
ssh '10.2.80.191' # 'kafka1'
ssh '10.2.76.11' # 'kafka5'
```

Anything that will only ever have a single instance will have a command
like `ssh_jenkins_instance` which just sshes directly there.

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

#### `ssh_*_instances`

There are tons of convenience aliases defined for you as well:

```
Fri Mar 10 15:28:37
tvisher@timvisher-rjmetrics.local
[read_only:59m]
~/git/ide (master *%>)
$ ssh_menagerie_instances
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q '10.2.82.200' # 'menagerie3'
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q '10.2.78.180' # 'menagerie4'

Fri Mar 10 15:29:52
tvisher@timvisher-rjmetrics.local
[read_only:58m]
~/git/ide (master *>)
$ ssh_sourcerer_service_instances
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q '10.2.82.137' # 'sourcerer-service2'
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q '10.2.76.195' # 'sourcerer-service3'
```

#### `ssh_instance`

```
Wed Mar 01 17:20:33
mbilyeu@matts-mbp
[read_only:50m]
~
$ ssh_instance stats
ssh '10.2.80.88' # 'dogstatsd1'
ssh '10.2.83.174' # 'stats-service2'
ssh '10.2.79.28' # 'stats-service4'
```

#### `delete_known_host_line`

Allows you to delete a line from your known_hosts file.

```
Thu Dec 15 10:23:56
tvisher@timvisher-rjmetrics.local
[prod_read_only:58m]
~
$ ssh '10.0.5.211' # 'loader-pg2'
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
…
Offending ECDSA key in /Users/tvisher/.ssh/known_hosts:210
…

Thu Dec 15 10:24:22
tvisher@timvisher-rjmetrics.local
[prod_read_only:58m]
~
$ delete_known_host_line 210

Thu Dec 15 10:26:36
tvisher@timvisher-rjmetrics.local
[prod_read_only:56m]
~
$ ssh '10.0.5.211' # 'loader-pg2'
…
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '10.0.5.211' (ECDSA) to the list of known hosts.
…
tvisher@loader-pg2:~$
```


### Editing environments

#### `edit_frontend_envs_[start|end]`

These functions allow you to:

- pull frontend environment files from S3
- verify that changes are valid JSON (using jq)
- show a diff of the changes in a dry-run
- commit the changes back to S3

example:

```
Wed Nov 02 12:39:45
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ edit_frontend_envs_start
# Prepped api for editing.
emacs ~/env_tmp/php-stitch-api.prod.environment.json
# Prepped dashboard for editing.
emacs ~/env_tmp/php-stitch-dashboard.prod.environment.json
Make your edits and then run edit_frontend_envs_end to verify your edits and copy your local environments back to s3

Wed Nov 02 12:41:08
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ emacs ~/env_tmp/php-stitch-api.prod.environment.json

Wed Nov 02 12:43:26
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ edit_frontend_envs_end
# Checking the following environments
api
dashboard
parse error: Expected separator between values at line 3, column 9
# /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json did not parse.
# See jq errors above for details
# Fix json

Wed Nov 02 12:43:37
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ echo 'See that json parse error? :)'
See that json parse error? :)

Wed Nov 02 12:43:55
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ emacs ~/env_tmp/php-stitch-api.prod.environment.json

Wed Nov 02 12:44:09
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ edit_frontend_envs_end
# Checking the following environments
api
dashboard
# All environment files parse
# Doing a dry run!
# edit_frontend_envs_end --commit # when you're ready
# Changes in api
--- /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json.bak     2016-11-02 12:41:07.000000000 -0400
+++ /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json 2016-11-02 12:44:04.000000000 -0400
@@ -1,4 +1,5 @@
 {
+    "charnock": true,
     "api": {
         "adminDataSource": {
             "host": "masterdb.internal.rjmetrics.com",
# No changes in dashboard

Wed Nov 02 12:44:15
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ echo "We're ready to commit"'!'
We're ready to commit!

Wed Nov 02 12:44:43
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ edit_frontend_envs_end --commit # when you're ready
# Checking the following environments
api
dashboard
# All environment files parse
# Presenting files to commit
--- /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json.bak     2016-11-02 12:41:07.000000000 -0400
+++ /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json 2016-11-02 12:44:04.000000000 -0400
@@ -1,4 +1,5 @@
 {
+    "charnock": true,
     "api": {
         "adminDataSource": {
             "host": "masterdb.internal.rjmetrics.com",
# Are you sure you want to commit the diff above for api? [y/N]: yes
# Not commiting changes to api
# dashboard had no changes

Wed Nov 02 12:45:01
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ echo "Only api was changed so only api attempted to commit. You _must_ enter 'y' specifically."
Only api was changed so only api attempted to commit. You _must_ enter 'y' specifically.

Wed Nov 02 12:45:23
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$ edit_frontend_envs_end --commit # when you're ready
# Checking the following environments
api
dashboard
# All environment files parse
# Presenting files to commit
--- /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json.bak     2016-11-02 12:41:07.000000000 -0400
+++ /Users/tvisher/env_tmp/php-stitch-api.prod.environment.json 2016-11-02 12:44:04.000000000 -0400
@@ -1,4 +1,5 @@
 {
+    "charnock": true,
     "api": {
         "adminDataSource": {
             "host": "masterdb.internal.rjmetrics.com",
# Are you sure you want to commit the diff above for api? [y/N]: y
# Successfully created backup
# aws s3 cp --recursive 's3://dev-deployment-assets/php-stitch-api-backups/2016-11-02T16:45:30Z' 's3://dev-deployment-assets/php-stitch-api' # to rollback
upload: ../../env_tmp/php-stitch-api.prod.environment.json to s3://dev-deployment-assets/php-stitch-api/prod/environment.json
# dashboard had no changes

Wed Nov 02 12:45:32
tvisher@timvisher-rjmetrics.local
~/git/ide (stitchdata-feature/edit-env-functions)
$
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

## emacs

It is assumed that you're running at least the latest stable version of
emacs, 25.1. You may need to install that from source depending on your
package manager.

### Installation

```
cd ~/git/ide/emacs
./install
```

This should fail if you have an existing ~/.emacs or ~/.emacs.d that
doesn't point to this project.

### General Notes

`C-x C-c` is disabled by default to accomodate using `org-mode` more
safely. `M-x kill-emacs` instead.

We bind `M-x` to `smex`.

You can use `ag` to search the current project using `C-c A`.

Several keys are bound to `expand-region` convenience functions under `C-c
r`.

We use `y-or-n-p` rather than `yes-or-no-p`.

`dired-x` is enabled.

`dired-dwim-target` is enabled.

We turn on `delete-selection-mode` so text entry with an active region
will replace that region (like it does in most other editors).

`sentence-end-double-space` is turned on.

`winner-mode` is turned on.

### Active repositories

- gnu
- marmalade
- melpa
- melpa-stable

### Selected Packages

- ag
- align-cljlet
- bats-mode
- better-defaults
- cider
- coffee-mode
- expand-region
- fixme-mode
- ido-ubiquitous
- ido-vertical-mode
- magit
- markdown-mode
- mediawiki
- org
- paredit
- php-mode
- projectile
- smex
- terraform-mode
- yaml-mode

### `M-x header-comment`

Prompts for and inserts a comment like the following:

```
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; foo
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
```

The length of the wrappers comes from `fill-column` and the comment
character is derived from the current mode.

### `C-c C`/`M-x rjmetrics-dired-code-dir`

Opens a dired buffer aimed at your VM's `/opt/code` directory.

### `M-x rjmetrics-clone-repo`

Clones a repo from the `RJMetrics` org into the current directory.

### `<f5>`/`M-x todo-frame-bounce`

Opens a dedicated frame for keeping a temporary org-mode todo list in the
current project.

If you're currently looking at the todo list, it takes you back to the
previous frame.

### `M-x github-source-link`

Echoes a link GitHub with the current active region highlighted to the
minibuffer.

### `M-x github-commit-link`

Echoes a link to the current commit at point to the minibuffer. With a
prefix arg, also attempts to browse it.

### `M-x github-compare`

Echoes a compare link for the current branch and upstream.

### `M-x github-add-my-public`

Add's your push remote to the current repository as a remote named
`public`.

### `M-Q`/`M-x unfill-paragraph`

Unfills the current paragrah.

## `ssh`

In order to make interacting with prod easier it's highly recommended that
you add the contents of
[`ssh/config`](https://github.com/stitchdata/ide/blob/master/ssh/config)
to your `~/.ssh/config` file.

## Rationale

The vast majority of our tooling for working with Stitch must exist on the
VM in order to be maintainable. This allows us to make a large number of
assumptions and thus reduce complexity and move quickly to provide it.

However, some things should be available from the host as well. You
shouldn't need a VM in order to list an s3 bucket, for instance, or ssh to
a prod box. You should _also_ be able to do these things from the VM, but
you shouldn't need to.

So everything that exists here should also exist on the VM, but everything
that it makes sense to also do from your host should exist here.

The general rule of thumb should be that if you would need to do something
outside the normal course of developing a feature (which a VM is required
to do) you should add the tooling here and then it will be included in the
VM.

## Compatibility

In general, whatever we do here must be compatible with Ubuntu LTS and
macOS 10.12.
