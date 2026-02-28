using System;
using UnityEngine;

/// <summary>
/// Periods of the day. Used for lighting, NPC schedules, and quest triggers.
/// </summary>
public enum TimeOfDay
{
    Morning,
    Afternoon,
    Evening,
    Night
}

/// <summary>
/// Manages the in-game time-of-day state machine.
///
/// This is a simple state machine (Morning → Afternoon → Evening → Night → Morning).
/// Transitions are triggered explicitly (by game events, not real-time).
///
/// Future: Could be extended to a real-time clock with configurable day length.
///
/// Usage:
///   var tod = ServiceLocator.Get&lt;TimeOfDayManager&gt;();
///   tod.OnTimeChanged += newTime => UpdateLighting(newTime);
///   tod.AdvanceTime(); // Morning → Afternoon
/// </summary>
public class TimeOfDayManager : IInitializable
{
    public TimeOfDay Current { get; private set; } = TimeOfDay.Morning;

    /// <summary>Fired when the time of day changes.</summary>
    public event Action<TimeOfDay> OnTimeChanged;

    public void Initialize()
    {
        Current = TimeOfDay.Morning;
        Debug.Log("[TimeOfDay] Initialized → Morning");
    }

    /// <summary>
    /// Advance to the next time period (Morning → Afternoon → Evening → Night → loop).
    /// Call this when the player completes a major activity (attend class, eat lunch, etc.).
    /// </summary>
    public void AdvanceTime()
    {
        Current = Current switch
        {
            TimeOfDay.Morning   => TimeOfDay.Afternoon,
            TimeOfDay.Afternoon => TimeOfDay.Evening,
            TimeOfDay.Evening   => TimeOfDay.Night,
            TimeOfDay.Night     => TimeOfDay.Morning,
            _ => TimeOfDay.Morning
        };

        Debug.Log($"[TimeOfDay] Advanced → {Current}");
        OnTimeChanged?.Invoke(Current);
    }

    /// <summary>
    /// Restore time from a save file.
    /// </summary>
    public void SetTimeOfDay(string timeOfDayName)
    {
        if (Enum.TryParse<TimeOfDay>(timeOfDayName, out var tod))
        {
            var previous = Current;
            Current = tod;

            if (previous != tod)
                OnTimeChanged?.Invoke(Current);
        }
        else
        {
            Debug.LogWarning($"[TimeOfDay] Unknown time: {timeOfDayName}");
        }
    }
}
