<p align="center">
  <img src="https://raw.githubusercontent.com/openpeeps/sunday/main/.github/sunday_publishing_platform.png" alt="Sunday Publishing Platform" width="256px" height="160px"><br>
  🌞 Sunday &mdash; A simple publishing platform powered by Supranim<br>
  Compiled &bullet; Lightweight &bullet; Fast &bullet; 👑 Written in Nim language
</p>

<p align="center">
  📦 <code>nimble install sunday</code> | ⬇️ <a href="https://github.com/openpeeps/sunday/releases">Download from GitHub</a>
</p>

<p align="center">
  📚 <a href="https://github.com/">API reference</a><br>
  <img src="https://github.com/openpeeps/sunday/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/sunday/workflows/docs/badge.svg" alt="Github Actions">
</p>

## Key Features
- Compiled, fast and lightweight with a small memory footprint
- Built on top of the [Supranim web framework](https://github.com/supranim/supranim)
- Posts, pages, comments, categories and tags
- User authentication and management
- Media management with file uploads
- Tiptap-based rich text editor
- Native plugin system for extensibility
- Beautiful dashboard UI powered by **Bootstrap5**
- Themes system for easy customization based on **Tim Engine**

> [!NOTE]
> Sunday is still in active development. Expect frequent updates and new features as we work towards a stable release.

## About
Sunday is an ambitious project to create the missing piece in the Nim ecosystem: a modern, good-looking, and easy-to-use publishing platform for indie developers, bloggers and content creators.

We are using the power of the [Nim programming language](https://github.com/nim-lang/) and the Supranim web framework to build a platform that is not only fast and efficient but also a joy to use and customize. There will be themes, native plugins, and a beautiful dashboard interface to manage your content! 🌞

## 😍 Screenshots
Here you can find some hot off-the-press screenshots of the current state of Sunday. Keep in mind that the UI is still a work in progress and may change significantly before the stable release.
<details>
  <summary>🔥 Click to expand screenshots 👀</summary>
  <img src="https://raw.githubusercontent.com/openpeeps/sunday/main/.github/screenshot_011.png" alt="Sunday Defaul Theme" width="100%"><img src="https://raw.githubusercontent.com/openpeeps/sunday/main/.github/screenshot_03.png" alt="Sunday Auth Preview" width="100%"><img src="https://raw.githubusercontent.com/openpeeps/sunday/main/.github/screenshot_021.png" alt="Sunday Dashboard Preview" width="100%">
</details>

## Development

> [!NOTE]
> Documentation is still a work in progress, many details are not yet documented, are incomplete or may be outdated.

#### Backend Development
If you want to contribute to Sunday, you must ensure you have [Nim installed](https://nim-lang.org/install.html) on your machine. Once installed, you can use Nimble, Nim's package manager to install and build Sunday:

Nimble will try install the latest stable version of Sunday
```
nimble install sunday
```

If you need the bleeding edge version, you can specifyi `#head` to install directly from the main branch on GitHub:
```
nimble install sunday@#head
```

Sunday is powered by the [Supranim web framework](https://github.com/supranim/supranim), so if you want to contribute to the core of Sunday, you should also familiarize yourself with Supranim and its architecture. Check out the [Sunday Documentation](https://docs.supranim.com) for more details on how to set up a development environment and contribute to the project.

#### Client Side Development
Currently, Sunday uses the npm package manager to manage client-side dependencies and Rollup as the module bundler. 

To build and watch for changes while developing the client-side code, you can run the following command in the root directory of the project:
```
npm run watch
```

To build the client-side code for production, you can run:
```
npm run build
```

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/sunday/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/sunday/fork)
- 🎉 Spread the word! **Tell your friends about Sunday**
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)
- 🥰 [Donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C)

### 🎩 License
Sunday Publishing Platform | `AGPLv3` license. [Made in 🇪🇺 EU by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2026 OpenPeeps & Contributors &mdash; All rights reserved.
