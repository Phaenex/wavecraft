---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: ''

---

## Example bug report template

> Don't worry if you have trouble getting some of this info. Just leave it out.

**Description of the bug**
> Please don't just say it's "not working".

**Steps to reproduce**
> Steps to reproduce the bug. This usually doesn't need to be super detailed.
1. Go to '...'
2. Click on '...'
3. See error message '...'

**Versions**
> Please complete the following information.
 - Wavecraft: [commit hash, or `git log -1 --format=%h`]
 - macOS: [e.g. "26.5.1 (25F70)". ` > About This Mac`]

**Hardware**
> Delete this part if you think it's probably not necessary.
 - Computer: [e.g. "MacBook Pro (14-inch, 2024, M4 Pro)". ` > About This Mac`]
 - Audio Device: [e.g. "Built-in Output. Manufacturer: Apple Inc. Output Channels: 2 [...]". `System Information app > Hardware > Audio`]

**Debug logs**
> If you think we might not be able to reproduce the bug on our own machines, it can help to
> install a debug build (`./build_and_install.sh -d`) and include its logs from Console.app
> (search for "Wavecraft" or "BGM"). This takes a little effort, so feel free to leave it
> out at first.

[Debug logs attached here]

**Other info**
> Anything else you want to add?

---

> Tips
> (Delete this section before posting.)
>  - See [the README's Troubleshooting section](../../README.md#troubleshooting) and
>    [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) first.
>  - If your bug is about per-app volume, auto-pause, or recording system audio (not the per-app EQ
>    or output-routing features this fork adds), it may already be a known upstream issue — check
>    [upstream Background Music's issues](https://github.com/kyleneideck/BackgroundMusic/issues)
>    too. Known upstream workarounds:
>     - Wavecraft currently only supports audio devices with two channels. Bluetooth devices often only have one.
>     - Volumes having no effect for certain apps: Microsoft Teams ([workaround](https://github.com/kyleneideck/BackgroundMusic/issues/268#issuecomment-604977210)), Zoom ([workaround](https://github.com/kyleneideck/BackgroundMusic/issues/396#issuecomment-741992157)), Discord ([workaround](https://github.com/kyleneideck/BackgroundMusic/issues/210#issuecomment-507048957), [see also](https://github.com/kyleneideck/BackgroundMusic/issues/267#issuecomment-617327850)), Chrome (sometimes)
