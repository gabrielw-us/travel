using UnityEngine;
using UnityEngine.Splines;

[ExecuteInEditMode]
public class CameraFollowSplineLookAt : MonoBehaviour
{
    [Header("Spline Settings")]
    public SplineContainer splineContainer;
    public float duration = 5f;
    public AnimationCurve easing = AnimationCurve.Linear(0, 0, 1, 1);
    public bool loop = true;
    [Tooltip("If true, the camera will loop backward along the spline instead of jumping to the start.")]
    public bool reverseLoop = false;
    [Tooltip("If true, reverse loop uses smooth transitions instead of hard direction changes.")]
    public bool smoothReverse = false;
    [Tooltip("Speed of the transition when changing direction at loop points (lower = smoother)")]
    public float loopTransitionSpeed = 1f;

    [Header("LookAt Settings")]
    public Transform lookAtTarget;
    public float lookAtSpeed = 5f;

    [Header("Rotation Control")]
    [Tooltip("Additional rotation offset applied to the camera (in degrees)")]
    public Vector3 rotationOffset = Vector3.zero;

    [Header("Preview Control")]
    [Tooltip("Enable preview mode to manually control camera position along spline")]
    public bool previewMode = false;
    [Range(0f, 1f)]
    [Tooltip("Manual control of camera position along spline (0 = start, 1 = end)")]
    public float previewPosition = 0f;

    private float t = 0f;
    private int direction = 1; // 1 = forward, -1 = backward
    private bool isTransitioning = false; // Used for smooth reverse transitions

    void Update()
    {
        if (splineContainer == null) return;

        float easedT;

        if (previewMode)
        {
            // Use preview position directly
            easedT = easing.Evaluate(previewPosition);
        }
        else
        {
            // Skip automatic movement in edit mode
            if (!Application.isPlaying) return;
            
            if (duration <= 0f) return;

            // Increment progress along the spline
            t += direction * Time.deltaTime / duration;

            if (loop)
            {
                if (reverseLoop)
                {
                    if (smoothReverse)
                    {
                        // Smooth direction changes at endpoints
                        if (t > 1f && direction == 1)
                        {
                            t = 1f;
                            direction = -1;
                            isTransitioning = true;
                        }
                        else if (t < 0f && direction == -1)
                        {
                            t = 0f;
                            direction = 1;
                            isTransitioning = true;
                        }
                        
                        // Apply smooth transition at direction changes
                        if (isTransitioning)
                        {
                            // Slow down the direction change
                            t += direction * Time.deltaTime / duration * loopTransitionSpeed;
                            
                            // Stop transitioning after a short period
                            if ((direction == 1 && t > 0.1f) || (direction == -1 && t < 0.9f))
                            {
                                isTransitioning = false;
                            }
                        }
                    }
                    else
                    {
                        // Hard direction changes at endpoints
                        if (t > 1f)
                        {
                            t = 1f;
                            direction = -1;
                        }
                        else if (t < 0f)
                        {
                            t = 0f;
                            direction = 1;
                        }
                    }
                }
                else
                {
                    // Regular loop - jump back to start
                    t %= 1f;
                }
            }
            else
            {
                t = Mathf.Clamp01(t);
            }

            // Apply easing
            easedT = easing.Evaluate(t);
        }

        // Move camera along spline
        transform.position = splineContainer.EvaluatePosition(easedT);

        // Rotate camera
        Quaternion baseRotation;
        if (lookAtTarget != null)
        {
            Vector3 directionToTarget = lookAtTarget.position - transform.position;
            if (directionToTarget != Vector3.zero)
            {
                Quaternion targetRotation = Quaternion.LookRotation(directionToTarget);
                baseRotation = Quaternion.Slerp(transform.rotation, targetRotation, lookAtSpeed * Time.deltaTime);
            }
            else
            {
                baseRotation = transform.rotation;
            }
        }
        else
        {
            baseRotation = Quaternion.LookRotation(splineContainer.EvaluateTangent(easedT));
        }

        // Apply rotation offset
        Quaternion offsetRotation = Quaternion.Euler(rotationOffset);
        transform.rotation = baseRotation * offsetRotation;
    }
}
