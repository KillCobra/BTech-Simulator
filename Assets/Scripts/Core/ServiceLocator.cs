using System;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Lightweight service locator for decoupled access to game services.
///
/// Usage:
///   - Register services during the BIND step in GameInitiator:
///       ServiceLocator.Register(new SaveSystem());
///
///   - Access from anywhere:
///       var save = ServiceLocator.Get&lt;SaveSystem&gt;();
///
/// Why not Singletons?
///   - Singletons create hidden dependencies and make testing hard.
///   - ServiceLocator keeps all registrations in one visible place (GameInitiator).
///   - Services can be swapped (e.g., MockSaveSystem for tests).
/// </summary>
public static class ServiceLocator
{
    private static readonly Dictionary<Type, object> Services = new();

    /// <summary>
    /// Register a service instance. Overwrites any existing registration of the same type.
    /// </summary>
    public static void Register<T>(T service) where T : class
    {
        var type = typeof(T);
        if (Services.ContainsKey(type))
        {
            Debug.LogWarning($"[ServiceLocator] Overwriting existing service: {type.Name}");
        }

        Services[type] = service;
    }

    /// <summary>
    /// Retrieve a registered service. Throws if not found.
    /// </summary>
    public static T Get<T>() where T : class
    {
        var type = typeof(T);
        if (Services.TryGetValue(type, out var service))
        {
            return (T)service;
        }

        throw new InvalidOperationException(
            $"[ServiceLocator] Service not found: {type.Name}. " +
            "Was it registered in GameInitiator?");
    }

    /// <summary>
    /// Try to retrieve a service without throwing if absent.
    /// </summary>
    public static bool TryGet<T>(out T service) where T : class
    {
        var type = typeof(T);
        if (Services.TryGetValue(type, out var obj))
        {
            service = (T)obj;
            return true;
        }

        service = null;
        return false;
    }

    /// <summary>
    /// Clear all registrations. Call between scenes or in tests.
    /// </summary>
    public static void Reset()
    {
        Services.Clear();
    }
}
