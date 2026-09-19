# Godot DevContainer Feature

Installs the Godot game engine into your development container.

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `version` | Godot version to install (e.g., "4.7.2", "latest") | latest |
| `flavor`  | Flavour of Godot to install, can be either "standard" or "dotnet" | standard

## Usage

Add to your `devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/yourusername/devcontainer-features/godot:1": {
      "version": "4.7.2",
      "flavor": "dotnet"
    }
  }
}