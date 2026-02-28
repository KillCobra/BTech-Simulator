using System;
using System.IO;
using UnityEngine;

/// <summary>
/// JSON-based save/load system.
///
/// Saves to Application.persistentDataPath which is:
///   Windows: %USERPROFILE%\AppData\LocalLow\{CompanyName}\{ProductName}\
///   Android: /data/data/{packagename}/files/
///
/// Usage:
///   var save = ServiceLocator.Get&lt;SaveSystem&gt;();
///   save.SaveGame(new SaveData { playerSceneName = "Classroom" });
///   var data = save.LoadGame();
/// </summary>
public class SaveSystem : IInitializable
{
    private const string SaveFileName = "save.json";

    private string SaveFilePath =>
        Path.Combine(Application.persistentDataPath, SaveFileName);

    public void Initialize()
    {
        Debug.Log($"[SaveSystem] Save path: {SaveFilePath}");
    }

    /// <summary>
    /// Serialize and write save data to disk.
    /// </summary>
    public void SaveGame(SaveData data)
    {
        try
        {
            data.lastSaveTimestamp = DateTime.UtcNow.ToString("o");
            string json = JsonUtility.ToJson(data, prettyPrint: true);
            File.WriteAllText(SaveFilePath, json);
            Debug.Log($"[SaveSystem] Game saved at {data.lastSaveTimestamp}");
        }
        catch (Exception e)
        {
            Debug.LogError($"[SaveSystem] Failed to save: {e.Message}");
        }
    }

    /// <summary>
    /// Load save data from disk. Returns null if no save exists.
    /// </summary>
    public SaveData LoadGame()
    {
        if (!File.Exists(SaveFilePath))
        {
            Debug.Log("[SaveSystem] No save file found.");
            return null;
        }

        try
        {
            string json = File.ReadAllText(SaveFilePath);
            var data = JsonUtility.FromJson<SaveData>(json);
            Debug.Log("[SaveSystem] Game loaded.");
            return data;
        }
        catch (Exception e)
        {
            Debug.LogError($"[SaveSystem] Failed to load: {e.Message}");
            return null;
        }
    }

    /// <summary>
    /// Delete the save file.
    /// </summary>
    public void DeleteSave()
    {
        if (File.Exists(SaveFilePath))
        {
            File.Delete(SaveFilePath);
            Debug.Log("[SaveSystem] Save deleted.");
        }
    }

    /// <summary>
    /// Check if a save file exists.
    /// </summary>
    public bool HasSave() => File.Exists(SaveFilePath);
}
