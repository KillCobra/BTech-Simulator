using UnityEngine;
using UnityEngine.InputSystem; // Required for the new system

[RequireComponent(typeof(Rigidbody))]
public class PlayerController : MonoBehaviour
{
    [Header("Movement Settings")]
    public float walkSpeed = 15f;    
    public float sprintSpeed = 25f;
    public float jumpForce = 10f;

    private Rigidbody rb;
    private Animator anim;
    private Vector2 moveInput;
    private bool isSprinting;

    void Start()
    {
        rb = GetComponent<Rigidbody>();
        anim = GetComponent<Animator>();

        // Keep the character upright
        rb.freezeRotation = true;

        // Lock the cursor (optional, since mouse is unused now)
        // Cursor.lockState = CursorLockMode.Locked;
    }

    void Update()
    {
        // 1. Get Movement and Sprint Input
        moveInput = Vector2.zero;
        if (Keyboard.current.wKey.isPressed) moveInput.y = 1;
        if (Keyboard.current.sKey.isPressed) moveInput.y = -1;
        if (Keyboard.current.aKey.isPressed) moveInput.x = -1;
        if (Keyboard.current.dKey.isPressed) moveInput.x = 1;

        isSprinting = Keyboard.current.leftShiftKey.isPressed;

        // 2. Face movement direction (if moving)
        Vector3 moveDir = new Vector3(moveInput.x, 0, moveInput.y).normalized;
        if (moveDir.magnitude > 0.1f)
        {
            Quaternion targetRotation = Quaternion.LookRotation(moveDir, Vector3.up);
            transform.rotation = targetRotation * Quaternion.Euler(-90f, 180f, 0f);
        }

        // 3. Jump
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

        Vector3 moveDir = new Vector3(moveInput.x, 0, moveInput.y).normalized;

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

    bool IsGrounded()
    {
        return Physics.Raycast(transform.position, Vector3.down, 1.1f);
    }
}
