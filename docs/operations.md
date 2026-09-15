# Installation, persistence and customization

## What is inside claudebox.run?

`claudebox.run` is a Bash wrapper followed by a gzip-compressed tar archive of the
project source. The non-text bytes after `__ARCHIVE_BELOW__` are that archive, not a
separate compiled ClaudeBox executable. The wrapper extracts it into
`~/.claudebox/source/` and runs `main.sh`. The application creates the
`~/.local/bin/claudebox` symlink.

The source of the wrapper is [`.builder/script_template_root.sh`](../.builder/script_template_root.sh);
[`.builder/build.sh`](../.builder/build.sh) packages it. The embedded SHA256 identifies
the cached archive for update decisions; it is not a publisher signature.

Inspect a downloaded installer without executing it:

```bash
awk '/^__ARCHIVE_BELOW__$/ {exit} {print}' claudebox.run
archive_line=$(awk '/^__ARCHIVE_BELOW__$/ {print NR + 1; exit}' claudebox.run)
tail -n +"$archive_line" claudebox.run | tar -tzf -
```

Or build directly from a source checkout:

```bash
git clone https://github.com/RchGrav/claudebox.git
cd claudebox
bash .builder/build.sh
./dist/claudebox.run profiles
```

Outputs are `dist/claudebox.run` and `dist/claudebox-<version>.tar.gz`. A source
checkout contains the latest merged changes even when published release assets
have not yet been rebuilt. This guide does not imply a new release was published.

## Where profiles and state live

`profiles.ini` is generated for each project; it is not a missing repository file.
Run `claudebox add python` (or another profile) from your project, then locate it:

```bash
find "$HOME/.claudebox/projects" -name profiles.ini -print
```

Shared state is under `~/.claudebox/projects/<project-id>/`; slot state is in the
hashed slot directories below it. `claudebox info` and `claudebox slots` expose the
current project's information. See [the slot workflow](../README.md#first-project-and-slots).

Normal containers are removed on exit, but mounted workspace and slot files remain.
Revoking a slot deletes its saved authentication and session history. Rebuilding an
image is different from revoking a slot: it regenerates installed image content.

## Read session logs from the host

The slot's `.claude/` directory is already a host bind mount. Session files are not
trapped inside a disposable container. Locate them with:

```bash
find "$HOME/.claudebox/projects" -type f -path '*/.claude/projects/*' -name '*.jsonl' -print
```

Point a log viewer at the corresponding slot's `.claude/projects/` directory using
that viewer's own path option. No additional mount or copy is needed. Logs can
contain prompts, source code and credentials, so choose what to share with external
tools. This documents host access, not compatibility with every third-party viewer.

## Keep an installed tool between runs

Use an administration shell for changes that belong in the project's Docker image:

```bash
claudebox shell admin
```

Admin mode enables sudo and disables the container firewall for that session.
On exit, ClaudeBox commits the container filesystem to the project image and removes
the stopped admin container. This affects all slots that use that project image.
Files in bind mounts are persisted on the host, not captured by `docker commit`.
A later image rebuild can replace manually installed tools; encode them in a profile
when reproducible rebuilds matter.

### Deno

Inside `claudebox shell admin`, install Deno using its supported npm installer:

```bash
npm install -g deno
deno --version
exit
```

Then run `claudebox shell` and `deno --version` to check the saved installation.
Node/npm are already supplied by the base image. See the official
[Deno installation documentation](https://docs.deno.com/runtime/getting_started/installation/).

### Choose a Java version

The current Java profile uses SDKMAN rather than a fixed Debian JDK 17 package.
Run `claudebox add java`, launch the project to build that profile, then open
`claudebox shell admin`:

```bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk list java
```

Choose an identifier from that listing and use `sdk install java <identifier>` and
`sdk default java <identifier>`. Multiple versions can remain installed; `sdk use
java <identifier>` changes only the current shell. Exit the admin shell to preserve
the installation. `java -version` in a later shell checks the selected default.
See [SDKMAN usage](https://sdkman.io/usage/). Available identifiers depend on the
current vendor catalog and container architecture.

## Customize a profile in source

The runtime profile definitions are in [`lib/config.sh`](../lib/config.sh).
`get_profile_packages` selects Debian packages; `get_profile_<name>` emits additional
Dockerfile instructions. `main.sh` combines the selected functions with
[`build/Dockerfile.project`](../build/Dockerfile.project).

To change an existing profile, edit its package/function definition and rebuild the
installer. To add a profile, also register its name and description in
`get_all_profile_names` and `get_profile_description`, define its dependencies in
`expand_profile`, and export its generator alongside the existing generators.
Dropping an arbitrary file into a profiles directory does not register a profile.

Use `claudebox add <name>` to select it and `claudebox rebuild` to rebuild the current
project image. Keep these source changes in your branch so an installation update
does not silently become your only copy of the customization.

## Environment and credentials

See [environment variables](../README.md#environment-variables) and
[SSH key configuration](../README.md#ssh-key-configuration). Docker reads `.env`
as data; it does not run shell code from the file. Its format is documented in
[Docker's run reference](https://docs.docker.com/reference/cli/docker/container/run/#set-environment-variables--e---env---env-file).
A read-only key mount prevents host-file modification, not key disclosure or use.
