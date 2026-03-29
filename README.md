# DevFileTypes

A minimal macOS app bundle that registers correct [Uniform Type Identifiers (UTIs)](https://developer.apple.com/documentation/uniformtypeidentifiers) for developer file extensions that macOS either misclassifies or doesn't recognize at all.

## Why This Exists

I started using [Bloom](https://bloomapp.club) as my file viewer and noticed a lot of my source files weren't showing up correctly in the preview pane. TypeScript files were being treated as video. Rust, Go, Vue, and Svelte files had no type information at all. Previews were broken, icons were wrong, and files that should have been trivially readable were opaque blobs.

The issue isn't with Bloom — it's with macOS itself. macOS relies on Uniform Type Identifiers (UTIs) to classify every file on disk. Apps like Bloom, Finder, Quick Look, and Spotlight all query this system to decide what a file is, how to preview it, and what icon to show. By default, macOS maps `.ts` to MPEG-2 Transport Stream (video) and `.r` to a legacy Rez resource file. Extensions like `.tsx`, `.vue`, `.rs`, `.go`, `.svelte`, and `.astro` have no mapping at all. None of these defaults are what a developer would expect.

If you browse your projects in Finder, Bloom, or any file explorer and you've noticed your source files look wrong — wrong icons, missing previews, files classified as media or unknown — this tool fixes that at the root cause.

## The Problem

macOS uses UTIs to determine what kind of file something is. This affects Quick Look previews, Finder metadata, file explorer apps, and Spotlight indexing. The specific issues fall into two categories:

**Misclassified extensions** — macOS maps these to the wrong type entirely:

- **`.ts`** is classified as `public.mpeg-2-transport-stream` (video) instead of TypeScript source code
- **`.r`** is classified as `com.apple.rez-source` (legacy Rez resource) instead of R language source

**Unknown extensions** — macOS has no idea what these are, assigning them opaque dynamic UTIs (`dyn.ah62d...`) with no type information:

- **`.tsx`, `.jsx`, `.vue`, `.svelte`, `.rs`, `.go`**, and dozens more are completely invisible to the type system

The downstream effects are pervasive: file explorers show generic or incorrect icons, Quick Look can't generate previews, Spotlight can't index content, and any app that relies on UTIs for file handling will make wrong decisions about these files.

## What This Does

DevFileTypes.app is a background-only app that does nothing when launched. Its sole purpose is to carry an `Info.plist` with `UTImportedTypeDeclarations` and `UTExportedTypeDeclarations` that tell macOS Launch Services how to classify dozens of developer file extensions as `public.source-code` / `public.plain-text`.

Once installed and registered, apps that query the UTType system will see correct type information for these files.

## Supported Extensions

### Overrides (extensions macOS maps to the wrong type)

| Extension             | macOS Default                   | Corrected To      |
| --------------------- | ------------------------------- | ----------------- |
| `.ts`, `.mts`, `.cts` | MPEG-2 Transport Stream (video) | TypeScript Source |
| `.r`, `.R`            | Rez Resource                    | R Source          |

### New Declarations (extensions macOS doesn't know about)

| Category              | Extensions                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------ |
| TypeScript/JavaScript | `.tsx`, `.jsx`                                                                                   |
| Web Frameworks        | `.vue`, `.svelte`, `.astro`                                                                      |
| Systems Languages     | `.rs`, `.go`, `.zig`, `.nim`                                                                     |
| JVM Languages         | `.kt`, `.kts`, `.scala`, `.sc`, `.groovy`, `.gvy`                                                |
| .NET                  | `.cs`, `.fs`, `.fsi`, `.fsx`                                                                     |
| Mobile                | `.dart`                                                                                          |
| Scripting             | `.lua`, `.coffee`                                                                                |
| Functional            | `.ex`, `.exs`, `.elm`, `.hs`, `.lhs`, `.ml`, `.mli`                                              |
| Config/IaC            | `.tf`, `.tfvars`, `.hcl`, `.toml`, `.nix`, `.dhall`                                              |
| Schema/API            | `.graphql`, `.gql`, `.proto`, `.prisma`                                                          |
| Stylesheets           | `.sass`, `.scss`, `.less`, `.styl`                                                               |
| Templates             | `.jade`, `.pug`, `.ejs`, `.hbs`, `.handlebars`, `.mustache`, `.twig`, `.jinja`, `.jinja2`, `.j2` |
| Documents             | `.mdx`, `.ipynb`                                                                                 |

## Install

```bash
# Fix UTI classification for dozens of developer file extensions
./install-devfiletypes.sh

# Install recommended companion tools (Quick Look previews + duti)
./install-companions.sh

# Set your editor as the default for developer file extensions
./set-default-editor.sh
```

The first script copies `DevFileTypes.app` to `/Applications` and registers it with Launch Services.

The second script prompts you to choose a Quick Look provider, then installs it along with [duti](#duti) via Homebrew. You can also skip the prompt:

```bash
./install-companions.sh --syntax-highlight   # Syntax Highlight + QLMarkdown + duti
./install-companions.sh --glance             # Glance + duti
```

The script handles conflicts automatically — switching from one Quick Look provider to the other removes the previous one first. Rerunning refreshes the Quick Look registration even if the apps are already installed.

The third script sets your preferred editor as the default "Open With" handler for developer file extensions that currently have macOS default handlers or no handler at all. If you've already configured an extension to open in a third-party editor, it's left alone. See [set-default-editor.sh](#set-default-editorsh) for details.

## Uninstall

```bash
./install-devfiletypes.sh --uninstall
./install-companions.sh --uninstall
./set-default-editor.sh --revert
```

## Verifying

Check a file's UTI with:

```bash
mdls -name kMDItemContentType -name kMDItemContentTypeTree /path/to/file.rs
```

You should see something like:

```
kMDItemContentType     = "dev.devfiletypes.rust-source"
kMDItemContentTypeTree = (
    "public.item",
    "public.text",
    "dev.devfiletypes.rust-source",
    "public.data",
    "public.source-code",
    "public.content",
    "public.plain-text"
)
```

## Recommended Companion Tools

DevFileTypes fixes the UTI classification layer — it tells macOS what your files _are_. But it doesn't handle how those files are _previewed_. For that, you need a Quick Look provider. The companion script offers two options:

### Option 1: Syntax Highlight + QLMarkdown

[Syntax Highlight](https://github.com/sbarex/SourceCodeSyntaxHighlight) adds syntax-highlighted Quick Look previews for source code files. It supports hundreds of language grammars, and you can configure themes, fonts, and line numbers. TypeScript `.ts` remains a known macOS limitation.

[QLMarkdown](https://github.com/sbarex/QLMarkdown) renders Markdown files as formatted HTML in Quick Look — tables, code blocks, math, and all. Without it, pressing Space on a `.md` file shows raw text.

Both apps are from the same developer, each focused on one job. This option gives deeper language coverage and richer Markdown rendering.

### Option 2: Glance

[Glance](https://github.com/chamburr/glance) is a single app that covers source code, Markdown, archives, and Jupyter notebooks. Less configurable than Syntax Highlight, but simpler — one app instead of two. TypeScript `.ts` remains a known macOS limitation.

### Why you need both DevFileTypes and a Quick Look provider

These tools operate at different layers. Quick Look providers fix previews — press Space in Finder and you get a nice rendered preview. But they don't change how macOS classifies files. Without DevFileTypes, a `.rs` file still shows up as an unknown type in Finder's Kind column, Bloom's file type labels, Spotlight indexing, and any app that queries the UTI system. DevFileTypes fixes that root classification; the Quick Look provider fixes the preview experience on top of it.

### duti

[duti](https://github.com/moretension/duti) lets you set default "open with" app handlers from the command line. It's installed by `./install-companions.sh` regardless of which Quick Look option you choose.

### set-default-editor.sh

A standalone tool that uses duti to set your preferred editor as the default handler for developer file extensions. It covers all extensions managed by DevFileTypes plus common ones like `.json`, `.yaml`, `.py`, `.rb`, `.sql`, and others that macOS often assigns to the wrong app. It only overrides extensions that currently have macOS default handlers or no handler at all — extensions you've already configured with a third-party editor are left alone.

I recommend [Zed](https://zed.dev) — it's fast, lightweight, native to macOS, and has built-in syntax highlighting for hundreds of languages. But any editor works.

```bash
./set-default-editor.sh                    # Interactive: scan, prompt, set
./set-default-editor.sh zed                # Set all Apple defaults to Zed
./set-default-editor.sh --check            # Show current state, change nothing
./set-default-editor.sh --revert           # Undo changes (restores from backup)
```

Supported editor shorthands: `zed`, `vscode`, `cursor`, `sublime`, `nova`, `webstorm`, `intellij`. You can also pass a raw bundle ID (e.g., `dev.zed.Zed`).

The script saves a backup of the original handlers to `~/.devfiletypes-editor-backup` on first run, so `--revert` restores previously assigned handlers. Extensions that had no handler before cannot be unset by duti. You can also manage backups explicitly:

```bash
./set-default-editor.sh --backup ~/my-backup    # Save current state
./set-default-editor.sh --restore ~/my-backup   # Restore from file
```

For manual per-extension control, use duti directly:

```bash
duti -s dev.zed.Zed .ts all
```

## Limitations

For `.ts`, `.mts`, `.cts`, and `.r`, Apple declares system-level UTIs (`public.mpeg-2-transport-stream`, `com.apple.rez-source`) that take priority in the default `UTType(filenameExtension:)` lookup on modern macOS. Our correct declarations are registered and discoverable — apps that use `UTType.types(tag:tagClass:conformingTo:)` or look up `dev.devfiletypes.typescript-source` directly will see them — but apps doing the naive single-type lookup will still get Apple's type.

This is a known, system-level limitation. Every existing tool acknowledges it:

- **Syntax Highlight**: _"Typescript `.ts` format cannot be handled because is reserved by macOS"_
- **Glance**: _"macOS doesn't allow the handling of some file types (e.g. `.plist`, `.ts` and `.xml`)"_

No third-party app can override Apple's system UTI declarations on modern macOS. The workarounds are:

- **Quick Look**: Install [Syntax Highlight](https://github.com/sbarex/SourceCodeSyntaxHighlight) for broad source-code preview support. TypeScript `.ts` remains a known macOS limitation.
- **Default app**: Use [duti](https://github.com/moretension/duti) to set which app opens `.ts` files
- **File explorer apps**: Ask the developer to use `UTType.types(tag:tagClass:conformingTo: .sourceCode)` instead of the naive `UTType(filenameExtension:)` — our declaration is visible through that API

## How It Works

macOS Launch Services scans app bundles in `/Applications` for UTI declarations in their `Info.plist`. DevFileTypes.app uses:

- **`UTExportedTypeDeclarations`** for `.ts` and `.r` (higher priority, needed to compete with Apple's system types)
- **`UTImportedTypeDeclarations`** for everything else (sufficient for extensions with no existing system declaration)

All declared types conform to `public.source-code` and/or `public.plain-text`, which tells macOS these are text files, not binary data or media.

## Building from Source

The app bundle contains just two files:

- `Contents/Info.plist` — the UTI declarations
- `Contents/MacOS/DevFileTypes` — a minimal executable (`int main(void) { return 0; }`)

To rebuild the executable:

```bash
make
```

This compiles `main.c` into the app bundle. You need both `make` and a C compiler (`cc`), which are available on macOS via Xcode or the Command Line Tools (`xcode-select --install`). On a fresh Mac, running `make` may prompt you to install those tools first.

To clean the built executable:

```bash
make clean
```

## License

Public domain. Do whatever you want with this.
