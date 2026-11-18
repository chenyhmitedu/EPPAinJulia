# EPPAinJulia

This workspace uses a project-local Julia toolchain to avoid the broken Windows Store `julia.exe` alias on this machine.

## Run the project

- Command Prompt or PowerShell: `./Start-Julia.cmd main.jl`
- PowerShell script variant: `powershell -ExecutionPolicy Bypass -File .\Start-Julia.ps1 main.jl`
- REPL: `./Start-Julia.cmd`

## Toolchain location

- Julia executable: `.tools/julia-1.10.12/bin/julia.exe`
- VS Code setting: `.vscode/settings.json`

## Why this exists

`julia` on `PATH` currently resolves to `C:\Users\Henry\AppData\Local\Microsoft\WindowsApps\julia.exe`, which is only a broken Store stub here. The bundled Julia avoids that alias and satisfies the project's `julia = "1.10"` compatibility in `Project.toml`.
