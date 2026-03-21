# roslyn-workspace-diagnostics.nvim

This plugin enables automatic workspace-wide diagnostics for Microsoft's [Roslyn LSP](https://github.com/dotnet/roslyn/tree/main/src/LanguageServer/Microsoft.CodeAnalysis.LanguageServer) used in the [Visual Studio Code C# Extension](https://github.com/dotnet/vscode-csharp).

By default, Neovim only pulls diagnostics for open buffers. This plugin triggers `workspace/diagnostic` requests and re-polls every 2 seconds after completion, so you get errors and warnings across your entire project.

In theory it should not be too difficult to get this to work with other LSPs that implement workspace diagnostics. If there is any interest we could make it more generic.

>[!IMPORTANT]
>This plugin is still in the early stages of development and is bound to be a bit buggy. There are a lot of scenarios I have not tested.
>If you run into any issues please raise an issue.

## How it works

Recent versions of Neovim added built-in support for `workspace/diagnostic` via `vim.lsp.buf.workspace_diagnostics()`. This plugin builds on top of that by:

1. Calling `vim.lsp.buf.workspace_diagnostics()` to trigger an initial pull.
2. Intercepting `client.request` to track when all in-flight `workspace/diagnostic` requests complete.
3. Scheduling the next pull 2 seconds after all responses arrive, avoiding overlapping requests.

This approach lets Neovim handle the actual request/response cycle and diagnostic rendering while the plugin just manages the polling loop.

Previous versions of this plugin handled the full `workspace/diagnostic` request/response cycle manually, including partial result handling via `$/progress` and setting diagnostics on buffers directly. However, a Neovim update introduced its own built-in workspace diagnostic support, which conflicted with the plugin's custom implementation. Rather than fighting against Neovim's internals, the plugin was rewritten to delegate diagnostic handling to Neovim and focus solely on the polling loop.

## Features

- Automatically polls for workspace diagnostics from Roslyn
- Optional `.csproj` file watcher for live diagnostics on NuGet package changes

## Requirements

- Neovim nightly (requires `vim.lsp.buf.workspace_diagnostics()`)
- This plugin only works with Microsoft's Roslyn LSP. It should work out of the box with [easy-dotnet](https://github.com/GustavEikaas/easy-dotnet.nvim), [roslyn.nvim](https://github.com/seblyng/roslyn.nvim) and the roslyn configuration in [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#roslyn_ls). If you have configured the LSP in some other way, be sure to add the name you used to the `roslyn_alias` config.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ziemcd/roslyn-workspace-diagnostics.nvim",
  opts = {},
}
```

## Configuration

```lua
require("roslyn-workspace-diagnostics").setup({
  -- LSP client names to treat as Roslyn
  roslyn_alias = { "easy_dotnet", "roslyn_ls", "roslyn" },

  -- Watch .csproj files and notify Roslyn on changes
  csproj_watcher = {
    enabled = false,
    -- Optional: provide a custom function to find .csproj files
    find_csproj_files = function(cwd) return { ... } end,
  },
})
```

### Configuration for the Roslyn LSP

When you set up Roslyn you need to set up the background_analysis setting in order for workspace diagnostics to work. Here is an example with [seblj/roslyn.nvim](https://github.com/seblyng/roslyn.nvim):
```lua
{
  "seblj/roslyn.nvim",
  ft = { "cs", "csproj" },
  opts = {
    config = {
      settings = {
        -- ...
        ["csharp|background_analysis"] = {
          dotnet_analyzer_diagnostics_scope = "openFiles",
          dotnet_compiler_diagnostics_scope = "fullSolution",
        },
        -- ...
      },
    },
    -- ...
  }
}
```

>[!IMPORTANT]
>I highly recommend configuring the Roslyn LSP with `dotnet_analyzer_diagnostics_scope = "openFiles"`. Setting it to `fullSolution` will have a significant impact on performance and might even cause the server to crash.

### Csproj Watcher

When `csproj_watcher.enabled` is set to `true`, the plugin uses `libuv` file watchers to monitor `.csproj` files in your workspace. When a `.csproj` file changes (e.g. after adding or removing a NuGet package), it sends a `workspace/didChangeWatchedFiles` notification to Roslyn so diagnostics update without needing to restart the LSP.

The reason for this is because Neovim does not implement [DidChangeWatchedFiles Notification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_didChangeWatchedFiles), or it does but only for Mac and Windows. So if you are using either of those operating systems you might not need to worry about a csproj watcher. I am using Linux so am unsure. (If anyone is using Mac or Windows please let me know or update the readme)

By default it recursively scans the current working directory for `.csproj` files, skipping `bin`, `obj`, and `.git` directories. You can provide your own `find_csproj_files` function if you need custom discovery logic.

The watcher also exposes `watch_file` and `unwatch_file` so you can add to what files are being watched.

```lua
local watcher = require("roslyn-workspace-diagnostics.lsp.watcher")

watcher.watch_file("/path/to/file.csproj")
watcher.unwatch_file("/path/to/file.csproj")
```

### Recommendations
If you're using C# and Neovim I recommend checking out
- [GustavEikaas/easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim), a very extensive plugin for all your .Net needs, including full Roslyn LSP integration
- [seblyng/roslyn.nvim](https://github.com/seblyng/roslyn.nvim), a minimal implementation for configuring the Roslyn LSP
- [bosvik/roslyn-diagnostics.nvim](https://github.com/bosvik/roslyn-diagnostics.nvim), plugin providing an alternative way to get workspace diagnostics via autocmds
