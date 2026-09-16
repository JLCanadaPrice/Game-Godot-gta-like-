using System.Collections;
using UnityEngine;

public class TrafficLight : MonoBehaviour
{
    // The material to be applied to the traffic light.
    [Tooltip("The original material used for the traffic light.")]
    public Material originalMat;

    // The textures representing the different light states.
    [Tooltip("Texture for the green light.")]
    public Texture2D greenLight;
    [Tooltip("Texture for the yellow light.")]
    public Texture2D yellowLight;
    [Tooltip("Texture for the red light.")]
    public Texture2D redLight;

    private Material mat; // Instance of the material used for the traffic light.

    // Enum to represent the possible states of the traffic light.
    public enum LightState { Off, On, Emergency }
    [Tooltip("The current state of the traffic light.")]
    public LightState currentState = LightState.Off;

    // Duration of each light state in seconds.
    [Tooltip("Duration of the green light in seconds.")]
    public float greenLightDuration = 5f;
    [Tooltip("Duration of the yellow light in seconds.")]
    public float yellowLightDuration = 2f;
    [Tooltip("Duration of the red light in seconds.")]
    public float redLightDuration = 5f;
    [Tooltip("Interval between blinks in emergency mode.")]
    public float emergencyBlinkInterval = 0.5f;

    private Coroutine lightCoroutine; // Reference to the current running coroutine (light cycle or emergency blink).

    void Start()
    {
        // Create a new material instance and assign it to the object's renderer.
        mat = Instantiate(originalMat);
        GetComponent<Renderer>().material = mat;

        // Set the initial light state.
        SetLightState();
    }

    // This function sets the current light state based on the `currentState` value.
    public void SetLightState()
    {
        // If there is an existing coroutine running, stop it.
        if (lightCoroutine != null)
        {
            StopCoroutine(lightCoroutine);
        }

        // Switch to the correct light state behavior based on `currentState`.
        switch (currentState)
        {
            case LightState.Off:
                TurnOffLight(); // Turn off the light.
                break;
            case LightState.On:
                lightCoroutine = StartCoroutine(LightCycle()); // Start the regular light cycle.
                break;
            case LightState.Emergency:
                lightCoroutine = StartCoroutine(EmergencyBlink()); // Start emergency blinking.
                break;
        }
    }

    // This coroutine controls the normal traffic light cycle (red -> yellow -> green -> yellow).
    private IEnumerator LightCycle()
    {
        while (true)
        {
            SetEmissionTexture(redLight); // Set the light texture to red.
            yield return new WaitForSeconds(redLightDuration); // Wait for the red light duration.

            SetEmissionTexture(yellowLight); // Set the light texture to yellow.
            yield return new WaitForSeconds(yellowLightDuration); // Wait for the yellow light duration.

            SetEmissionTexture(greenLight); // Set the light texture to green.
            yield return new WaitForSeconds(greenLightDuration); // Wait for the green light duration.

            SetEmissionTexture(yellowLight); // Set the light texture to yellow again before switching back to red.
            yield return new WaitForSeconds(yellowLightDuration); // Wait for the yellow light duration.
        }
    }

    // This coroutine handles the emergency blinking pattern (yellow light on and off).
    private IEnumerator EmergencyBlink()
    {
        while (true)
        {
            SetEmissionTexture(yellowLight); // Set the light texture to yellow.
            yield return new WaitForSeconds(emergencyBlinkInterval); // Wait for the emergency blink interval.

            TurnOffEmission(); // Turn off the light (no emission).
            yield return new WaitForSeconds(emergencyBlinkInterval); // Wait again before blinking back on.
        }
    }

    // This function sets the texture to be used for the emission map (the glowing part of the material).
    private void SetEmissionTexture(Texture2D lightTexture)
    {
        mat.SetTexture("_EmissionMap", lightTexture); // Set the emission map texture.
        mat.EnableKeyword("_EMISSION"); // Enable the emission effect on the material.
    }

    // This function disables the emission effect, turning off the glowing light.
    private void TurnOffEmission()
    {
        mat.DisableKeyword("_EMISSION"); // Disable the emission effect on the material.
    }

    // This function turns off the traffic light by disabling the emission effect.
    private void TurnOffLight()
    {
        TurnOffEmission(); // Disable emission to turn off the light.
    }
}
