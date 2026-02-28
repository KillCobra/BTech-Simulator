using NUnit.Framework;

namespace BTechSimulator.Tests.EditMode
{
    /// <summary>
    /// Tests for GameStateManager state machine transitions.
    /// Category "Core" matches the CI shard selector.
    /// </summary>
    [TestFixture]
    [Category("Core")]
    public class GameStateTests
    {
        [Test]
        public void Initial_State_Is_None()
        {
            var manager = new GameStateManager();
            Assert.AreEqual(GameState.None, manager.CurrentState);
        }

        [Test]
        public void Initialize_Sets_State_To_Loading()
        {
            var manager = new GameStateManager();
            manager.Initialize();
            Assert.AreEqual(GameState.Loading, manager.CurrentState);
        }

        [Test]
        public void TransitionTo_Changes_State()
        {
            var manager = new GameStateManager();
            manager.Initialize();
            manager.TransitionTo(GameState.Playing);

            Assert.AreEqual(GameState.Playing, manager.CurrentState);
        }

        [Test]
        public void TransitionTo_Fires_Event_With_Correct_Args()
        {
            var manager = new GameStateManager();
            manager.Initialize();

            GameState capturedFrom = GameState.None;
            GameState capturedTo = GameState.None;

            manager.OnStateChanged += (from, to) =>
            {
                capturedFrom = from;
                capturedTo = to;
            };

            manager.TransitionTo(GameState.Playing);

            Assert.AreEqual(GameState.Loading, capturedFrom);
            Assert.AreEqual(GameState.Playing, capturedTo);
        }

        [Test]
        public void TransitionTo_Same_State_Does_Not_Fire_Event()
        {
            var manager = new GameStateManager();
            manager.Initialize(); // → Loading

            bool fired = false;
            manager.OnStateChanged += (_, _) => fired = true;

            manager.TransitionTo(GameState.Loading); // same state

            Assert.IsFalse(fired);
        }

        [Test]
        public void Multiple_Transitions_Track_Correctly()
        {
            var manager = new GameStateManager();
            manager.Initialize();

            manager.TransitionTo(GameState.Playing);
            manager.TransitionTo(GameState.Paused);
            manager.TransitionTo(GameState.Playing);

            Assert.AreEqual(GameState.Playing, manager.CurrentState);
        }
    }
}
