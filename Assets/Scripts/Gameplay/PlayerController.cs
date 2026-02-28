using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// Camera-relative player movement controller.
/// Movement is relative to whichever camera is tagged "MainCamera".
/// WASD moves, Shift sprints, Space jumps.
///
/// SINGLE ENTRY POINT: No Start() — GameInitiator calls Initialize() + EnableMovement().
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class PlayerController : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float walkSpeed = 6f;
    [SerializeField] private float sprintSpeed = 10f;
    [SerializeField] private float jumpForce = 6f;
    [SerializeField] private float rotationSpeed = 10f;

    [Header("Ground Check")]
    [SerializeField] private float groundCheckDistance = 1.5f;
    [SerializeField] private float groundCheckRadius = 0.3f;

    [Header("Model Offset (if mesh forward != Unity Z+)")]
    [SerializeField] private Vector3 modelRotationOffset = Vector3.zero;

    private Rigidbody _rb;
    private Animator _anim;
    private Vector2 _moveInput;
    private bool _isSprinting;
    private bool _movementEnabled;
    private Vector3 _worldMoveDir;
    private bool _jumpRequested;

    // ─── PUBLIC API (called by GameInitiator) ────────────────────────

    public void Initialize()
    {
        _rb = GetComponent<Rigidbody>();
        _anim = GetComponent<Animator>();

        _rb.constraints = RigidbodyConstraints.FreezeRotation;
        _rb.isKinematic = false;
        _rb.useGravity = true;
        _movementEnabled = false;

        if (_anim != null)
            _anim.applyRootMotion = false;
    }

    public void SetPosition(Vector3 position) => transform.position = position;
    public void EnableMovement() => _movementEnabled = true;

    public void DisableMovement()
    {
        _movementEnabled = false;
        _moveInput = Vector2.zero;
        _worldMoveDir = Vector3.zero;
    }

    // ─── PRIVATE LOGIC ───────────────────────────────────────────────

    private void Update()
    {
        if (!_movementEnabled || Keyboard.current == null) return;

        // Read input
        _moveInput = Vector2.zero;
        if (Keyboard.current.wKey.isPressed) _moveInput.y += 1;
        if (Keyboard.current.sKey.isPressed) _moveInput.y -= 1;
        if (Keyboard.current.aKey.isPressed) _moveInput.x -= 1;
        if (Keyboard.current.dKey.isPressed) _moveInput.x += 1;

        _isSprinting = Keyboard.current.leftShiftKey.isPressed;
        _worldMoveDir = GetCameraRelativeDirection(_moveInput);

        // Rotate toward movement direction
        if (_worldMoveDir.sqrMagnitude > 0.01f)
        {
            Quaternion target = Quaternion.LookRotation(_worldMoveDir, Vector3.up);

            if (modelRotationOffset != Vector3.zero)
                target *= Quaternion.Euler(modelRotationOffset);

            transform.rotation = Quaternion.Slerp(
                transform.rotation, target, Time.deltaTime * rotationSpeed);
        }

        // Jump
        if (Keyboard.current.spaceKey.wasPressedThisFrame && IsGrounded())
            _jumpRequested = true;

        UpdateAnimation();
    }

    private void FixedUpdate()
    {
        if (!_movementEnabled || _rb == null) return;

        float speed = _isSprinting ? sprintSpeed : walkSpeed;
        Vector3 velocity = new Vector3(
            _worldMoveDir.x * speed,
            _rb.linearVelocity.y,
            _worldMoveDir.z * speed);

        if (_jumpRequested)
        {
            velocity.y = jumpForce;
            _jumpRequested = false;
        }

        _rb.linearVelocity = velocity;
    }

    // ─── CAMERA-RELATIVE DIRECTION ───────────────────────────────────

    private static Vector3 GetCameraRelativeDirection(Vector2 input)
    {
        if (input.sqrMagnitude < 0.01f)
            return Vector3.zero;

        Camera cam = Camera.main;
        if (cam == null)
            cam = FindAnyObjectByType<Camera>();

        if (cam == null)
            return new Vector3(input.x, 0f, input.y).normalized;

        Vector3 camForward = Vector3.ProjectOnPlane(cam.transform.forward, Vector3.up).normalized;
        Vector3 camRight = Vector3.Cross(Vector3.up, camForward).normalized;

        return (camForward * input.y + camRight * input.x).normalized;
    }

    // ─── ANIMATION ───────────────────────────────────────────────────

    private void UpdateAnimation()
    {
        if (_anim == null) return;

        bool isMoving = _worldMoveDir.sqrMagnitude > 0.01f;
        _anim.SetBool("isMoving", isMoving);
        _anim.SetBool("isSprinting", _isSprinting && isMoving);
    }

    // ─── GROUND CHECK ────────────────────────────────────────────────

    private bool IsGrounded()
    {
        Vector3 origin = transform.position + Vector3.up * 0.5f;
        return Physics.SphereCast(origin, groundCheckRadius, Vector3.down, out _, groundCheckDistance);
    }
}
