using UnityEngine;

public class SwitchCamera : MonoBehaviour
{
    public GameObject Camera1;
    public GameObject Camera2;
    public int Manager;

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
    }
    void Cam_2()
    {
        Camera1.SetActive(false);
        Camera2.SetActive(true);
    }
}
