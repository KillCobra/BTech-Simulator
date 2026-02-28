using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// Player movement controller (2.5D).
///
/// SINGLE ENTRY POINT PATTERN:
///   - NO Start() method — initialization is done via Initialize() called by GameInitiator.
///   - Movement is DISABLED by default until EnableMovement() is called.
///   - Public methods expose setup that used to happen independently.
///
/// GameInitiator usage:
///   var player = Instantiate(playerPrefab);
///   var controller = player.GetComponent&lt;PlayerController&gt;();
///   controller.Initialize();                    // BIND step
///   controller.SetPosition(spawnPoint);         // PREPARE step
///   controller.EnableMovement();                // START GAME step
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class PlayerController : MonoBehaviour
{
    [Header("Movement Settings")]
    [SerializeField] private float walkSpeed = 15f;
    [SerializeField] private float sprintSpeed = 25f;
    [SerializeField] private float jumpForce = 10f;

    private Rigidbody _rb;
    private Animator _anim;
    private Vector2 _moveInput;
    private bool _isSprinting;
    private bool _movementEnabled;

    // ─── PUBLIC API (called by GameInitiator) ────────────────────────

    /// <summary>
    /// Initialize component references.
    /// Called during the BIND/INITIALIZE step instead of Start().
    /// </summary>
    public void Initialize()
    {
        _rb = GetComponent<Rigidbody>();
        _anim = GetComponent<Animator>();
        _rb.freezeRotation = true;
        _movementEnabled = false;
    }

    /// <summary>
    /// Place the player at a specific world position.
    /// Called during the PREPARE step.
    /// </summary>
    public void SetPosition(Vector3 position)
    {
        transform.position = position;
    }

    /// <summary>
    /// Allow the player to move. Called during the START GAME step.
    /// </summary>
    public void EnableMovement()
    {
        _movementEnabled = true;
    }

    /// <summary>
    /// Freeze the player (e.g., during cutscenes, loading, dialogue).
    /// </summary>
    public void DisableMovement()
    {
        _movementEnabled = false;
        _moveInput = Vector2.zero;
    }

    // ─── PRIVATE LOGIC ───────────────────────────────────────────────

    private void Update()
    {
        if (!_movementEnabled) return;

        // 1. Read input
        _moveInput = Vector2.zero;
        if (Keyboard.current.wKey.isPressed) _moveInput.y = 1;
        if (Keyboard.current.sKey.isPressed) _moveInput.y = -1;
        if (Keyboard.current.aKey.isPressed) _moveInput.x = -1;
        if (Keyboard.current.dKey.isPressed) _moveInput.x = 1;

        _isSprinting = Keyboard.current.leftShiftKey.isPressed;

        // 2. Face movement direction
        Vector3 moveDir = new Vector3(_moveInput.x, 0, _moveInput.y).normalized;
        if (moveDir.magnitude > 0.1f)
        {
            Quaternion targetRotation = Quaternion.LookRotation(moveDir, Vector3.up);
            transform.rotation = targetRotation * Quaternion.Euler(-90f, 180f, 0f);
        }

        // 3. Jump
        if (Keyboard.current.spaceKey.wasPressedThisFrame && IsGrounded())
        {
            _rb.AddForce(Vector3.up * jumpForce, ForceMode.Impulse);
        }

        // 4. Update Animator
        UpdateAnimation();
    }

    private void FixedUpdate()
    {
        if (!_movementEnabled) return;

        float speed = _isSprinting ? sprintSpeed : walkSpeed;
        Vector3 moveDir = new Vector3(_moveInput.x, 0, _moveInput.y).normalized;

        _rb.linearVelocity = new Vector3(
            moveDir.x * speed,
            _rb.linearVelocity.y,
            moveDir.z * speed
        );
    }

    private void UpdateAnimation()
    {
        if (_anim == null) return;

        bool isMoving = _moveInput.magnitude > 0.1f;
        _anim.SetBool("isMoving", isMoving);
        _anim.SetBool("isSprinting", _isSprinting && isMoving);
    }

    private bool IsGrounded()
    {
        return Physics.Raycast(transform.position, Vector3.down, 1.1f);
    }
}
