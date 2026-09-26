using UnityEngine;

/// <summary>
/// Switches between two cameras. The active camera always gets the
/// "MainCamera" tag so that Camera.main (and camera-relative movement)
/// automatically follows whichever view is currently active.
/// </summary>
public class SwitchCamera : MonoBehaviour
{
    public GameObject Camera1;
    public GameObject Camera2;
    public int Manager;

    /// <summary>
    /// Set the starting camera's tag to "MainCamera" immediately,
    /// so Camera.main works from the very first frame.
    /// WITHOUT THIS, Camera.main returns null and the player cannot move.
    /// </summary>
    private void Awake()
    {
        if (Manager == 0)
        {
            if (Camera1 != null) Camera1.tag = "MainCamera";
            if (Camera2 != null) Camera2.tag = "Untagged";
        }
        else
        {
            if (Camera2 != null) Camera2.tag = "MainCamera";
            if (Camera1 != null) Camera1.tag = "Untagged";
        }
    }

    public void ChangeCamera()
    {
        GetComponent<Animator>().SetTrigger("Change");
    }
    public void ManageCamera()
    {
        if (Manager == 0)
        {
            Cam_2();
            Manager = 1;
        }
        else
        {
            Cam_1();
            Manager = 0;
        }
    }

    void Cam_1()
    {
        Camera1.SetActive(true);
        Camera2.SetActive(false);

        // The ACTIVE camera must be tagged "MainCamera" — this is the ONLY tag
        // that Camera.main recognizes. Custom tags like "Camera1" won't work.
        Camera1.tag = "MainCamera";
        Camera2.tag = "Untagged";
    }
    void Cam_2()
    {
        Camera1.SetActive(false);
        Camera2.SetActive(true);

        Camera2.tag = "MainCamera";
        Camera1.tag = "Untagged";
    }
}
