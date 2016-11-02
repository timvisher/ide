# The Stitch IDE

The definitive collection of tooling that should work on your host for
working with Stitch.

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

To get started, set up your `iam` profile using `aws --profile iam
configure` and your AWS provided key pair and then run
`configure_aws_profiles`.

`configure_aws_profiles` will set up the following profiles:

- `dev_admin_global`
- `prod_admin`
- `prod_admin_global`
- `prod_read_only`
- `stitch_dev_admin_global`
- `stitch_prod_admin`
- `stitch_prod_admin_global`

You can then use them either by `set_default_profile` or by `assume_*`.

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
$ set_default_profile stitch_prod_read_only

Fri Oct 28 16:31:34
tvisher@timvisher-rjmetrics.local
[default profile: stitch_prod_read_only]
~
$
```

Use `unassume_role` to unset your default role.

#### `assume_*`

If you need to assume an AWS role for a tool other than the aws cli you'll
need to export the proper environment variables.

You can initialize a shell with a new role using one of the `assume_*`
convenience aliases.

```
Mon Oct 31 13:42:43
tvisher@timvisher-rjmetrics.local
~/git/ide
$ assume_stitch_prod_read_only 484610

Mon Oct 31 13:42:58
tvisher@timvisher-rjmetrics.local
[stitch_prod_read_only:59m]
~/git/ide
$
```

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
[stitch_prod_read_only:51m]
~/git/ide
$
```

To see your currently cached roles and when they're good till you can run
`pp_role_caches`.

```
Tue Nov 01 11:24:48
tvisher@timvisher-rjmetrics.local
[stitch_dev_admin_global:41m]
~/git/ide
$ pp_role_caches
assume_stitch_dev_admin_global 123456 # 41m
assume_stitch_prod_admin_global 123456 # 39m

```

Variables take precedence over the default profile.

To see the currently cached role you can use `pp_role_cache`.

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
