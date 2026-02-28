using System;
using System.Threading.Tasks;
using UnityEngine;

/// <summary>
/// THE SINGLE ENTRY POINT for the entire game.
/// This is the ONLY MonoBehaviour that should have a Start() method in the boot scene.
///
/// Flow Steps (from the Single Entry Point pattern):
///   1. BIND        – Create/resolve references to prefabs and services
///   2. LOADING     – Show loading screen immediately
///   3. INITIALIZE  – Setup services that need init (analytics, input, SDKs)
///   4. CREATE      – Load heavy objects / scenes asynchronously
///   5. PREPARE     – Position objects, load save data, configure appearance
///   6. START GAME  – Hide loading screen, begin gameplay
///
/// All other scripts should expose PUBLIC methods called from here.
/// No other script should have independent Start/Awake game-flow logic.
/// </summary>
public class GameInitiator : MonoBehaviour
{
    // ─── BINDINGS (Step 1) ───────────────────────────────────────────
    // Drag prefabs / scene references here in the Inspector.
    // This is the ONE organized place that holds all game references.

    [Header("UI")]
    [SerializeField] private LoadingScreen loadingScreenPrefab;

    [Header("Scene Configuration")]
    [SerializeField] private string firstSceneName = "InitialHostel";

    // ─── RUNTIME REFERENCES ─────────────────────────────────────────
    private LoadingScreen _loadingScreen;

    // ═══════════════════════════════════════════════════════════════════
    //  THE ONLY START() IN THE ENTIRE GAME
    // ═══════════════════════════════════════════════════════════════════
    private async void Start()
    {
        try
        {
            await InitializeGame();
        }
        catch (Exception e)
        {
            Debug.LogError($"[GameInitiator] Fatal error during initialization: {e}");
        }
    }

    private async Task InitializeGame()
    {
        // =============================================
        // STEP 1: BIND – Create/resolve references
        // =============================================
        Debug.Log("[GameInitiator] Step 1: Binding...");

        // Register core services into the ServiceLocator.
        // Any class can later call ServiceLocator.Get<T>() to access these.
        ServiceLocator.Register(new SceneLoader());
        ServiceLocator.Register(new SaveSystem());
        ServiceLocator.Register(new GameStateManager());
        ServiceLocator.Register(new TimeOfDayManager());

        // =============================================
        // STEP 2: SHOW LOADING SCREEN (as early as possible)
        // =============================================
        Debug.Log("[GameInitiator] Step 2: Showing loading screen...");

        if (loadingScreenPrefab != null)
        {
            _loadingScreen = Instantiate(loadingScreenPrefab);
            DontDestroyOnLoad(_loadingScreen.gameObject);
            _loadingScreen.Show();
        }

        SetProgress(0.1f, "Initializing services...");

        // =============================================
        // STEP 3: INITIALIZE – Setup services
        // =============================================
        Debug.Log("[GameInitiator] Step 3: Initializing services...");

        var saveSystem = ServiceLocator.Get<SaveSystem>();
        saveSystem.Initialize();
        SetProgress(0.2f, "Save system ready");

        var gameState = ServiceLocator.Get<GameStateManager>();
        gameState.Initialize();
        SetProgress(0.25f, "Game state ready");

        var timeManager = ServiceLocator.Get<TimeOfDayManager>();
        timeManager.Initialize();
        SetProgress(0.3f, "Time system ready");

        // ─── Initialize third-party services here ───
        // await AnalyticsService.Initialize();
        // await AuthenticationService.Initialize();
        // await RemoteConfigService.FetchAsync();

        // =============================================
        // STEP 4: CREATE – Load heavy objects / scenes
        // =============================================
        Debug.Log("[GameInitiator] Step 4: Creating game world...");

        var sceneLoader = ServiceLocator.Get<SceneLoader>();
        await sceneLoader.LoadSceneAsync(firstSceneName, _loadingScreen, 0.3f, 0.7f);
        SetProgress(0.7f, "World loaded");

        // =============================================
        // STEP 5: PREPARE – Position objects, load data
        // =============================================
        Debug.Log("[GameInitiator] Step 5: Preparing game...");

        // Load save data if it exists
        SaveData saveData = saveSystem.LoadGame();
        if (saveData != null)
        {
            timeManager.SetTimeOfDay(saveData.timeOfDay);
            // Restore any other saved state here:
            // player.SetPosition(saveData.playerPosition.ToVector3());
        }

        SetProgress(0.85f, "Preparing player...");

        // ─── Find and initialize the player in the loaded scene ───
        var player = FindAnyObjectByType<PlayerController>();
        if (player != null)
        {
            player.Initialize();
            Debug.Log("[GameInitiator] Player initialized.");
        }
        else
        {
            Debug.LogWarning("[GameInitiator] No PlayerController found in scene.");
        }

        SetProgress(0.9f, "Almost ready...");

        // =============================================
        // STEP 6: START GAME – Hide loading, begin gameplay
        // =============================================
        Debug.Log("[GameInitiator] Step 6: Starting game!");

        gameState.TransitionTo(GameState.Playing);

        // Enable player movement now that the game is playing
        if (player != null)
            player.EnableMovement();

        SetProgress(1.0f, "Starting...");

        // Brief pause so user sees 100%
        await Task.Delay(300);

        if (_loadingScreen != null)
            _loadingScreen.Hide();

        Debug.Log("[GameInitiator] ✓ Game started successfully!");
    }

    /// <summary>
    /// Helper to update loading screen progress + status in one call.
    /// </summary>
    private void SetProgress(float progress, string status = null)
    {
        if (_loadingScreen == null) return;
        _loadingScreen.SetProgress(progress);
        if (!string.IsNullOrEmpty(status))
            _loadingScreen.SetStatus(status);
    }
}
