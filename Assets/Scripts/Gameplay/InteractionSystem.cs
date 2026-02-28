using System;
using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// Detects nearby IInteractable objects and triggers interaction on input.
/// Attach this to the Player GameObject alongside the PlayerController.
///
/// Setup:
///   1. Create a Layer called "Interactable"
///   2. Assign that layer to all interactable GameObjects
///   3. Set interactableLayer in the Inspector to that layer
///
/// Fires events so UI can show/hide the interaction prompt without coupling.
/// </summary>
public class InteractionSystem : MonoBehaviour
{
    [Header("Detection")]
    [SerializeField] private float interactionRange = 2.5f;
    [SerializeField] private LayerMask interactableLayer;

    // ─── Events for UI to listen to ───
    /// <summary>Fired when a new interactable enters range. Arg: the interactable.</summary>
    public event Action<IInteractable> OnInteractableFound;

    /// <summary>Fired when the current interactable leaves range.</summary>
    public event Action OnInteractableLost;

    /// <summary>Fired after a successful interaction. Arg: the interactable.</summary>
    public event Action<IInteractable> OnInteracted;

    private IInteractable _currentInteractable;

    /// <summary>
    /// Initialize with custom settings. Called by GameInitiator during PREPARE step.
    /// </summary>
    public void Setup(float range, LayerMask layer)
    {
        interactionRange = range;
        interactableLayer = layer;
    }

    private void Update()
    {
        // Only process when game is in Playing state
        if (!ServiceLocator.TryGet<GameStateManager>(out var gsm) ||
            gsm.CurrentState != GameState.Playing)
        {
            return;
        }

        DetectNearbyInteractable();

        // Check for interact input
        if (_currentInteractable != null &&
            Keyboard.current != null &&
            Keyboard.current.eKey.wasPressedThisFrame)
        {
            if (_currentInteractable.CanInteract)
            {
                _currentInteractable.OnInteract();
                OnInteracted?.Invoke(_currentInteractable);
            }
        }
    }

    private void DetectNearbyInteractable()
    {
        var colliders = Physics.OverlapSphere(
            transform.position,
            interactionRange,
            interactableLayer
        );

        IInteractable nearest = null;
        float nearestDist = float.MaxValue;

        foreach (var col in colliders)
        {
            if (col.TryGetComponent<IInteractable>(out var interactable) &&
                interactable.CanInteract)
            {
                float dist = Vector3.Distance(transform.position, col.transform.position);
                if (dist < nearestDist)
                {
                    nearestDist = dist;
                    nearest = interactable;
                }
            }
        }

        // Notify UI when the interactable changes
        if (nearest != _currentInteractable)
        {
            if (_currentInteractable != null)
                OnInteractableLost?.Invoke();

            _currentInteractable = nearest;

            if (_currentInteractable != null)
                OnInteractableFound?.Invoke(_currentInteractable);
        }
    }

    private void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.yellow;
        Gizmos.DrawWireSphere(transform.position, interactionRange);
    }
}
