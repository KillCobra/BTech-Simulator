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
                Debug.Log($"[Autosave - {reason}] Scene saved at {DateTime.Now:HH:mm:ss}");
            }
            else
            {
                Debug.Log($"[Autosave - {reason}] No changes to save at {DateTime.Now:HH:mm:ss}");
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

    // Manual save menu item
    [MenuItem("Tools/Autosave/Save Now")]
    private static void ManualSave()
    {
        PerformAutosave("Manual");
        lastSaveTime = DateTime.Now;
    }

    // Change interval menu items
    [MenuItem("Tools/Autosave/Set Interval (1 min)")]
    private static void SetInterval1Min()
    {
        autosaveInterval = 60f;
        lastSaveTime = DateTime.Now;
        Debug.Log("[Autosave] Interval set to 1 minute.");
    }

    [MenuItem("Tools/Autosave/Set Interval (2 min)")]
    private static void SetInterval2Min()
    {
        autosaveInterval = 120f;
        lastSaveTime = DateTime.Now;
        Debug.Log("[Autosave] Interval set to 2 minutes.");
    }

    [MenuItem("Tools/Autosave/Set Interval (5 min)")]
    private static void SetInterval5Min()
    {
        autosaveInterval = 300f;
        lastSaveTime = DateTime.Now;
        Debug.Log("[Autosave] Interval set to 5 minutes.");
    }
}
