/// <summary>
/// Implement on any service or system that requires setup during the
/// INITIALIZE step of the game startup sequence.
///
/// Example:
///   public class AnalyticsService : IInitializable
///   {
///       public void Initialize() { /* connect to backend */ }
///   }
/// </summary>
public interface IInitializable
{
    void Initialize();
}
