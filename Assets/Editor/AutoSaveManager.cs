using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using System;

public class AutoSaveManager : MonoBehaviour
{
    private static float autosaveInterval = 60f; // 1 minute in seconds
    private static DateTime lastSaveTime = DateTime.Now;
    private static bool isAutosaving = false;

    [InitializeOnLoadMethod]
    private static void Initialize()
    {
        EditorApplication.update += CheckAutosave;
        EditorApplication.playModeStateChanged += OnPlayModeStateChanged;
        Debug.Log("[Autosave] Initialized. Saving every minute and before play mode.");
    }

    private static void CheckAutosave()
    {
        if (isAutosaving)
            return;

        // Check if enough time has passed since last save
        if ((DateTime.Now - lastSaveTime).TotalSeconds >= autosaveInterval)
        {
            PerformAutosave("Interval");
            lastSaveTime = DateTime.Now;
        }
    }

    private static void OnPlayModeStateChanged(PlayModeStateChange state)
    {
        // Save before entering play mode
        if (state == PlayModeStateChange.ExitingEditMode)
        {
            PerformAutosave("Before Play");
            lastSaveTime = DateTime.Now;
        }
    }

    private static void PerformAutosave(string reason)
    {
        if (EditorApplication.isPlayingOrWillChangePlaymode && reason != "Before Play")
        {
            return;
        }

        isAutosaving = true;

        try
        {
            var scene = EditorSceneManager.GetActiveScene();
            
            // Only save if scene has unsaved changes
            if (scene.isDirty)
            {
                EditorSceneManager.SaveScene(scene);
            }
            else
            {
            }

            // Save all assets
            AssetDatabase.SaveAssets();
        }
        catch (System.Exception ex)
        {
            Debug.LogError($"[Autosave] Failed: {ex.Message}");
        }
        finally
        {
            isAutosaving = false;
        }
    }
}
