using UnityEngine;
using UnityEngine.UI;
using TMPro;

/// <summary>
/// Full-screen loading overlay with progress bar and status text.
/// Create as a prefab with a Canvas → CanvasGroup → Panel → Slider + TMP_Text.
///
/// The GameInitiator instantiates this as the FIRST thing in the game,
/// and it persists across scenes via DontDestroyOnLoad.
///
/// Usage (called by GameInitiator):
///   _loadingScreen.Show();
///   _loadingScreen.SetProgress(0.5f);
///   _loadingScreen.SetStatus("Loading world...");
///   _loadingScreen.Hide();
/// </summary>
public class LoadingScreen : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private CanvasGroup canvasGroup;
    [SerializeField] private Slider progressBar;
    [SerializeField] private TextMeshProUGUI statusText;

    [Header("Settings")]
    [SerializeField] private float smoothSpeed = 3f;

    private float _targetProgress;
    private bool _isVisible;

    private void Awake()
    {
        if (canvasGroup == null)
            canvasGroup = GetComponent<CanvasGroup>();

        // Start hidden
        canvasGroup.alpha = 0f;
        gameObject.SetActive(false);
    }

    /// <summary>Show the loading screen immediately.</summary>
    public void Show()
    {
        gameObject.SetActive(true);
        _isVisible = true;
        canvasGroup.alpha = 1f;
        _targetProgress = 0f;

        if (progressBar != null)
            progressBar.value = 0f;
    }

    /// <summary>Hide the loading screen immediately.</summary>
    public void Hide()
    {
        _isVisible = false;
        canvasGroup.alpha = 0f;
        gameObject.SetActive(false);
    }

    /// <summary>Set the target progress (0–1). Bar smoothly interpolates.</summary>
    public void SetProgress(float progress)
    {
        _targetProgress = Mathf.Clamp01(progress);
    }

    /// <summary>Update the status message below the progress bar.</summary>
    public void SetStatus(string message)
    {
        if (statusText != null)
            statusText.text = message;
    }

    private void Update()
    {
        if (!_isVisible || progressBar == null) return;

        // Smoothly interpolate the progress bar
        progressBar.value = Mathf.MoveTowards(
            progressBar.value,
            _targetProgress,
            Time.unscaledDeltaTime * smoothSpeed
        );
    }
}
