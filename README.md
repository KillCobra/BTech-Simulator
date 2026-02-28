# BTech Simulator

A 2.5D game for autistic college-going kids — built with Unity 6 (6000.3.9f1), URP, and the new Input System.

## Architecture: Single Entry Point Pattern

This project follows the **Single Entry Point** pattern where the entire game flow starts from one place — `GameInitiator` in the `_Boot` scene.

### Why?

- **No black screen on load** — Loading screen shows immediately
- **Synchronized flow** — No race conditions between Start/Awake across scripts
- **Clear dependency chain** — One place holds all references
- **Team-friendly** — Empty scenes = fewer merge conflicts
- **Scalable** — Easy to add new initialization steps without breaking existing ones

### Boot Flow (6 Steps)

```
_Boot scene loads → GameInitiator.Start() runs
    │
    ├── 1. BIND         Register services (SaveSystem, SceneLoader, etc.)
    ├── 2. LOADING      Show loading screen immediately
    ├── 3. INITIALIZE   Setup services (analytics, input, save system)
    ├── 4. CREATE       Load game scene (HostelRoom) additively
    ├── 5. PREPARE      Restore save data, position player, configure world
    └── 6. START GAME   Hide loading screen, transition to Playing state
```

### Key Rules

1. **Only `GameInitiator` has a `Start()` method** for game flow
2. Other scripts expose **public methods** called by the initiator
3. Scripts are **decoupled** — they don't reference each other directly
4. Use `ServiceLocator.Get<T>()` to access shared services
5. The `_Boot` scene is **empty** except for the `GameInitiator` GameObject

---

## Project Structure

```
Assets/
├── Scripts/
│   ├── Core/                    ← Game bootstrap & architecture
│   │   ├── GameInitiator.cs       Single entry point (THE Start method)
│   │   ├── BootstrapLoader.cs     Forces boot scene in builds
│   │   ├── ServiceLocator.cs      Lightweight dependency injection
│   │   ├── GameState.cs           State machine (Loading/Playing/Paused)
│   │   └── IInitializable.cs      Interface for services needing init
│   │
│   ├── Systems/                 ← Infrastructure services
│   │   ├── SceneLoader.cs         Async additive scene loading
│   │   ├── SaveSystem.cs          JSON save/load
│   │   └── SaveData.cs            Serializable save container
│   │
│   ├── Gameplay/                ← Game mechanics
│   │   ├── IInteractable.cs       Interface for interactable objects
│   │   ├── InteractionSystem.cs   Proximity detection + E key
│   │   └── TimeOfDayManager.cs    Morning/Afternoon/Evening/Night cycle
│   │
│   ├── UI/                      ← User interface
│   │   └── LoadingScreen.cs       Progress bar overlay
│   │
│   └── PlayerMovement.cs        ← Player controller (refactored)
│
├── Tests/
│   ├── EditMode/                ← Unit tests (Category: Core)
│   │   ├── Core/
│   │   │   ├── ServiceLocatorTests.cs
│   │   │   ├── GameStateTests.cs
│   │   │   └── TimeOfDayTests.cs
│   │   └── Systems/
│   │       └── SaveSystemTests.cs
│   │
│   └── PlayMode/                ← Integration tests (Category: Integration)
│       └── Core/
│           └── BootFlowTests.cs
│
├── Scenes/
│   ├── _Boot.unity              ← Create this! (see setup below)
│   ├── InitialHostel.unity
│   └── SampleScene.unity
│
├── IMPORTED/                    ← 3D models & imported assets
├── Editor/                      ← Editor-only tools
└── Settings/                    ← URP render pipeline settings
```

---

## Getting Started

### 1. Create the `_Boot` Scene

1. In Unity: **File → New Scene → Empty Scene**
2. Save as `Assets/Scenes/_Boot.unity`
3. Create an empty GameObject, name it **"GameInitiator"**
4. Attach the `GameInitiator` script to it
5. (Optional) Create a Loading Screen prefab and assign it

### 2. Set Build Scene Order

1. **File → Build Settings**
2. Add scenes in this order:
   - `_Boot` (index 0 — always first!)
   - `InitialHostel`
   - Any future scenes (Classroom, Cafeteria, etc.)

### 3. Create a Loading Screen Prefab

1. Create a **Canvas** with a `CanvasGroup` component
2. Add a **Panel** (dark background)
3. Add a **Slider** (progress bar)
4. Add a **TextMeshPro** text (status message)
5. Attach the `LoadingScreen` script, wire up references
6. Save as prefab, assign to `GameInitiator`

### 4. Setup Interactables

1. Create a **Layer** called `Interactable` in the Tag Manager
2. Add `InteractionSystem` to the Player alongside `PlayerController`
3. Implement `IInteractable` on any object the player can interact with:

```csharp
public class DoorInteractable : MonoBehaviour, IInteractable
{
    public string PromptText => "Open Door";
    public bool CanInteract => true;

    public void OnInteract()
    {
        // Load the next scene, play animation, etc.
        var loader = ServiceLocator.Get<SceneLoader>();
        _ = loader.TransitionToScene("Classroom", ...);
    }
}
```

---

## CI/CD Pipeline

| Trigger | What runs |
|---------|-----------|
| Push to feature branch | EditMode + PlayMode tests (Core & Integration shards) |
| Pull Request to main | Reuses push test results or runs tests as fallback |
| Merge to main | Full build (StandaloneWindows64) + artifact upload (7 days) |

Tests use Unity Test Framework categories matching CI shards:
- `[Category("Core")]` — Unit tests for pure logic
- `[Category("Integration")]` — PlayMode tests requiring MonoBehaviour lifecycle

---

## Coding Conventions

- **Private fields**: `_camelCase` prefix
- **Public properties**: `PascalCase`
- **One class per file** (except small data types like `SaveData`/`Vector3Serializable`)
- **No `Start()`/`Awake()` for game flow** — only `GameInitiator` orchestrates startup
- **Use `[SerializeField] private`** instead of `public` for Inspector fields
- See `.editorconfig` for full style rules

---

## Team Workflow

- **3 members**, branching: `main` (protected) → `dev` → `feature/*`
- Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`
- Git LFS enabled for binary assets (see `.gitattributes`)
- Scene ownership: each person works on separate scenes to avoid conflicts
- The `_Boot` scene is nearly empty — safe for everyone

---

## Roadmap (from Jira Backlog)

### Sprint 1: Playable Hostel Room
- [x] Project bootstrap (URP, Input System, CI)
- [x] Single Entry Point architecture
- [x] Character controller (2.5D movement)
- [ ] Hostel Room scene (greybox → first pass)
- [ ] Interaction system (bed, desk, door)
- [ ] Loading screen UI
- [ ] Save/Load (JSON)

### Sprint 2: Classroom + Cafeteria
- [ ] Classroom scene
- [ ] Cafeteria scene
- [ ] Scene transitions (room → corridor → classroom)
- [ ] NPC interaction framework
- [ ] Dialogue system (lightweight)
- [ ] Time-of-day state machine (visual)
- [ ] Schedule UI

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Engine | Unity 6000.3.9f1 |
| Render Pipeline | URP 17.3 |
| Input | New Input System 1.18 |
| Testing | Unity Test Framework 1.6 |
| CI/CD | GitHub Actions + GameCI |
| Version Control | Git + LFS |
