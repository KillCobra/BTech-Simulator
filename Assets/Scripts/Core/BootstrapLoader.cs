using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>
/// Ensures the game always starts from the _Boot scene in builds,
/// regardless of which scene the build player opens first.
///
/// In the Editor, this is SKIPPED so designers can hit Play in any scene
/// for quick testing. To test the full boot flow in the Editor,
/// open the _Boot scene manually and press Play.
///
/// No MonoBehaviour or GameObject needed — uses [RuntimeInitializeOnLoadMethod].
/// </summary>
public static class BootstrapLoader
{
    private const string BootSceneName = "_Boot";

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    private static void OnBeforeSceneLoad()
    {
        // Already in the boot scene — nothing to do
        if (SceneManager.GetActiveScene().name == BootSceneName)
            return;

        // In builds: force-redirect to the boot scene so GameInitiator runs first.
        // In the editor: skip so devs can test individual scenes freely.
#if !UNITY_EDITOR
        Debug.Log($"[Bootstrap] Redirecting to {BootSceneName} scene...");
        SceneManager.LoadScene(BootSceneName);
#endif
    }
}
