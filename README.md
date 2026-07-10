# Dotfiles

## Installation

- Clone repository to `~/dotfiles`.
- Run `~/dotfiles/init` to clone the external repos (e.g. [dotvim](https://github.com/saaguero/dotvim) into `~/dotvim`).
- If you are using Mac:
  - `~/dotfiles/brew-init` to install the packages.
  - `~/dotfiles/macos-init` to set up the macOS defaults.
- Copy the dotfiles and configs with `~/dotfiles/dotsync`.

On any change, you need to re-run `dotsync` to apply the changes.

## LanguageTool

To set up a local LanguageTool instance with Spanish n-grams and fastText:

- Run `~/dotfiles/languagetool-init` (Homebrew mode, default).
- Run `~/dotfiles/languagetool-init --docker` to use Docker instead.

## Credits

- [Mathias Bynens](https://github.com/mathiasbynens/dotfiles/)
- [Nick Nisi](https://github.com/nicknisi/dotfiles)
- [ThePrimeagen](https://github.com/ThePrimeagen/dev)
