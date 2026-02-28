using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.SceneManagement;

/// <summary>
/// Handles asynchronous scene loading/unloading with progress reporting.
///
/// The game uses ADDITIVE scene loading:
///   - _Boot scene stays loaded always (holds GameInitiator + LoadingScreen)
///   - Game scenes (HostelRoom, Classroom, Cafeteria) load on top of _Boot
///   - Scene transitions unload the old scene and load the new one
///
/// Usage (from GameInitiator or any controller):
///   var loader = ServiceLocator.Get&lt;SceneLoader&gt;();
///   await loader.LoadSceneAsync("Classroom", loadingScreen, 0.3f, 0.7f);
/// </summary>
public class SceneLoader
{
    /// <summary>Current additively-loaded game scene name (null if none).</summary>
    public string CurrentSceneName { get; private set; }

    /// <summary>
    /// Loads a scene additively with progress reporting mapped to [progressStart, progressEnd].
    /// </summary>
    public async Task LoadSceneAsync(
        string sceneName,
        LoadingScreen loadingScreen = null,
        float progressStart = 0f,
        float progressEnd = 1f)
    {
        Debug.Log($"[SceneLoader] Loading scene: {sceneName}");

        var operation = SceneManager.LoadSceneAsync(sceneName, LoadSceneMode.Additive);
        if (operation == null)
        {
            Debug.LogError($"[SceneLoader] Failed to start loading scene: {sceneName}. " +
                           "Is it added to Build Settings?");
            return;
        }

        operation.allowSceneActivation = false;

        while (!operation.isDone)
        {
            // Unity reports 0 → 0.9 for loading, then pauses at 0.9 until activation
            float progress = Mathf.Clamp01(operation.progress / 0.9f);
            float mapped = Mathf.Lerp(progressStart, progressEnd, progress);
            loadingScreen?.SetProgress(mapped);

            if (operation.progress >= 0.9f)
            {
                operation.allowSceneActivation = true;
            }

            await Task.Yield();
        }

        CurrentSceneName = sceneName;

        // Clean up duplicates caused by additive loading
        CleanupDuplicates();

        Debug.Log($"[SceneLoader] Scene loaded: {sceneName}");
    }

    /// <summary>
    /// After loading a scene additively, the new scene may bring its own
    /// Camera (with AudioListener) and EventSystem. Unity only wants one
    /// of each, so we destroy the extras — keeping the ones from _Boot.
    /// </summary>
    private static void CleanupDuplicates()
    {
        // Keep only the first AudioListener
        var listeners = Object.FindObjectsByType<AudioListener>(FindObjectsSortMode.None);
        for (int i = 1; i < listeners.Length; i++)
        {
            Debug.Log($"[SceneLoader] Destroying duplicate AudioListener on '{listeners[i].gameObject.name}'");
            Object.Destroy(listeners[i]);
        }

        // Keep only the first EventSystem
        var eventSystems = Object.FindObjectsByType<EventSystem>(FindObjectsSortMode.None);
        for (int i = 1; i < eventSystems.Length; i++)
        {
            Debug.Log($"[SceneLoader] Destroying duplicate EventSystem on '{eventSystems[i].gameObject.name}'");
            Object.Destroy(eventSystems[i].gameObject);
        }
    }

    /// <summary>
    /// Unloads a scene asynchronously.
    /// </summary>
    public async Task UnloadSceneAsync(string sceneName)
    {
        Debug.Log($"[SceneLoader] Unloading scene: {sceneName}");

        var operation = SceneManager.UnloadSceneAsync(sceneName);
        if (operation == null)
        {
            Debug.LogWarning($"[SceneLoader] Scene not loaded or cannot be unloaded: {sceneName}");
            return;
        }

        while (!operation.isDone)
        {
            await Task.Yield();
        }

        if (CurrentSceneName == sceneName)
            CurrentSceneName = null;

        Debug.Log($"[SceneLoader] Scene unloaded: {sceneName}");
    }

    /// <summary>
    /// Full scene transition: show loading → unload old → load new → hide loading.
    /// Use this for moving between gameplay scenes (e.g., HostelRoom → Classroom).
    /// </summary>
    public async Task TransitionToScene(
        string toScene,
        LoadingScreen loadingScreen)
    {
        var gameState = ServiceLocator.Get<GameStateManager>();
        gameState.TransitionTo(GameState.SceneTransition);

        loadingScreen?.Show();
        loadingScreen?.SetProgress(0f);

        // Unload old scene if one is loaded
        if (!string.IsNullOrEmpty(CurrentSceneName))
        {
            await UnloadSceneAsync(CurrentSceneName);
            loadingScreen?.SetProgress(0.3f);
        }

        // Load new scene
        await LoadSceneAsync(toScene, loadingScreen, 0.3f, 0.9f);

        loadingScreen?.SetProgress(1f);
        await Task.Delay(200);

        loadingScreen?.Hide();
        gameState.TransitionTo(GameState.Playing);
    }
}
