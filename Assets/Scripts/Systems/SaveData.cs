using System;
using UnityEngine;

/// <summary>
/// Serializable save data container.
/// Add new fields as features are built. Bump saveVersion when the format changes.
///
/// Uses Vector3Serializable because UnityEngine.Vector3 doesn't serialize to JSON cleanly.
/// </summary>
[Serializable]
public class SaveData
{
    public int saveVersion = 1;
    public string lastSaveTimestamp;

    [Header("Player")]
    public string playerSceneName = "InitialHostel";
    public Vector3Serializable playerPosition;

    [Header("Time")]
    public string timeOfDay = "Morning";

    [Header("Progress Flags")]
    public bool hasAttendedLecture;
    public bool hasEatenLunch;
    public bool hasCompletedTutorial;

    // Add new save fields here as features are built:
    // public int currency;
    // public string[] completedQuests;
    // public string currentObjective;
}

/// <summary>
/// JSON-safe Vector3 wrapper since Unity's Vector3 doesn't round-trip through JsonUtility well.
/// </summary>
[Serializable]
public struct Vector3Serializable
{
    public float x;
    public float y;
    public float z;

    public Vector3Serializable(Vector3 v)
    {
        x = v.x;
        y = v.y;
        z = v.z;
    }

    public Vector3 ToVector3() => new(x, y, z);

    public static implicit operator Vector3Serializable(Vector3 v) => new(v);
    public static implicit operator Vector3(Vector3Serializable v) => v.ToVector3();
}
