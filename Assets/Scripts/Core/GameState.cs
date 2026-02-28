using System;
using UnityEngine;

/// <summary>
/// All possible high-level game states.
/// Add new states as the game grows (e.g., Cutscene, Dialogue, Menu).
/// </summary>
public enum GameState
{
    None,
    Loading,
    Playing,
    Paused,
    SceneTransition
}

/// <summary>
/// Manages the current game state and notifies listeners on transitions.
///
/// Usage:
///   var gsm = ServiceLocator.Get&lt;GameStateManager&gt;();
///   gsm.OnStateChanged += (from, to) => Debug.Log($"{from} → {to}");
///   gsm.TransitionTo(GameState.Playing);
/// </summary>
public class GameStateManager : IInitializable
{
    public GameState CurrentState { get; private set; } = GameState.None;

    /// <summary>
    /// Fired whenever the state changes. Args: (previousState, newState).
    /// </summary>
    public event Action<GameState, GameState> OnStateChanged;

    public void Initialize()
    {
        CurrentState = GameState.Loading;
        Debug.Log("[GameState] Initialized → Loading");
    }

    /// <summary>
    /// Transition to a new state. No-op if already in that state.
    /// </summary>
    public void TransitionTo(GameState newState)
    {
        if (CurrentState == newState) return;

        var previous = CurrentState;
        CurrentState = newState;

        Debug.Log($"[GameState] {previous} → {newState}");
        OnStateChanged?.Invoke(previous, newState);
    }
}
