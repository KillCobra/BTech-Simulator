using UnityEngine;
using UnityEngine.InputSystem; // Required for the new system

[RequireComponent(typeof(Rigidbody))]
public class PlayerController : MonoBehaviour
{
    [Header("Movement Settings")]
    public float walkSpeed = 15f;    // Increased for your Scale 100 character
    public float sprintSpeed = 25f;
    public float jumpForce = 10f;
    public float mouseSensitivity = 0.1f;

    private Rigidbody rb;
    private Animator anim;
    private float yRot;
    private Vector2 moveInput;
    private bool isSprinting;

    void Start()
    {
        rb = GetComponent<Rigidbody>();
        anim = GetComponent<Animator>();

        // Keep the character upright
        rb.freezeRotation = true;

        // Lock the cursor to the game window
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
    }

    void Update()
    {
        // 1. Get Movement and Sprint Input
        moveInput = Vector2.zero;
        if (Keyboard.current.wKey.isPressed) moveInput.y = -1;
        if (Keyboard.current.sKey.isPressed) moveInput.y = 1;
        if (Keyboard.current.aKey.isPressed) moveInput.x = 1;
        if (Keyboard.current.dKey.isPressed) moveInput.x = -1;

        isSprinting = Keyboard.current.leftShiftKey.isPressed;

        // 2. Mouse Look
        Vector2 mouseDelta = Mouse.current.delta.ReadValue();
        yRot += mouseDelta.x * mouseSensitivity;
        transform.rotation = Quaternion.Euler(-90f, yRot, 0f);

        // 3. Jump (Input System style)
        if (Keyboard.current.spaceKey.wasPressedThisFrame && IsGrounded())
        {
            rb.AddForce(Vector3.up * jumpForce, ForceMode.Impulse);
        }

        // 4. Update Animator
        UpdateAnimation();
    }

   void FixedUpdate()
{
    float speed = isSprinting ? sprintSpeed : walkSpeed;

    // We add a '-' before moveInput.y to flip the Forward/Backward direction
    // We use transform.up because with a -90 X rotation, 'Up' is actually pointing 'Forward'
    Vector3 moveDir = (transform.up * -moveInput.y + transform.right * moveInput.x).normalized;

    rb.linearVelocity = new Vector3(
        moveDir.x * speed,
        rb.linearVelocity.y,
        moveDir.z * speed
    );
}
    void UpdateAnimation()
    {
        if (anim == null) return;

        bool isMoving = moveInput.magnitude > 0.1f;
        anim.SetBool("isMoving", isMoving);
        anim.SetBool("isSprinting", isSprinting && isMoving);
    }

    // Simple check to see if we are on the floor before jumping
    bool IsGrounded()
    {
        // Shoots a tiny ray down to check for the floor
        return Physics.Raycast(transform.position, Vector3.down, 1.1f);
    }
}