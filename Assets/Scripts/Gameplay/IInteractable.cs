/// <summary>
/// Interface for objects the player can interact with in the world.
/// Attach to any GameObject with a Collider and an "Interactable" layer.
///
/// Example:
///   public class Door : MonoBehaviour, IInteractable
///   {
///       public string PromptText => "Open Door";
///       public bool CanInteract => !isLocked;
///       public void OnInteract() { /* open the door */ }
///   }
/// </summary>
public interface IInteractable
{
    /// <summary>Text shown in the UI prompt (e.g., "Press [E] to Open").</summary>
    string PromptText { get; }

    /// <summary>Whether this object can currently be interacted with.</summary>
    bool CanInteract { get; }

    /// <summary>Called when the player confirms interaction.</summary>
    void OnInteract();
}
