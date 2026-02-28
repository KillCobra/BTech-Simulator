using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace BTechSimulator.Tests.PlayMode
{
    /// <summary>
    /// PlayMode integration tests for the boot flow.
    /// Category "Integration" matches the CI shard selector: -testCategory Integration
    ///
    /// These tests run in Play Mode and can test MonoBehaviour lifecycle.
    /// </summary>
    [TestFixture]
    [Category("Integration")]
    public class BootFlowTests
    {
        [SetUp]
        public void SetUp()
        {
            ServiceLocator.Reset();
        }

        [TearDown]
        public void TearDown()
        {
            ServiceLocator.Reset();
        }

        [UnityTest]
        public IEnumerator ServiceLocator_Survives_Frame()
        {
            var gsm = new GameStateManager();
            ServiceLocator.Register(gsm);

            yield return null; // wait one frame

            var retrieved = ServiceLocator.Get<GameStateManager>();
            Assert.AreSame(gsm, retrieved);
        }

        [UnityTest]
        public IEnumerator GameState_Transition_During_Play()
        {
            var gsm = new GameStateManager();
            gsm.Initialize();
            ServiceLocator.Register(gsm);

            yield return null;

            gsm.TransitionTo(GameState.Playing);

            yield return null;

            Assert.AreEqual(GameState.Playing, gsm.CurrentState);
        }

        [UnityTest]
        public IEnumerator LoadingScreen_Can_Be_Instantiated()
        {
            // Create a minimal loading screen GameObject at runtime
            var go = new GameObject("TestLoadingScreen");
            var canvasGroup = go.AddComponent<CanvasGroup>();
            var loadingScreen = go.AddComponent<LoadingScreen>();

            yield return null; // let Awake run

            // Should start hidden after Awake
            Assert.AreEqual(0f, canvasGroup.alpha, 0.01f);

            // Show it
            loadingScreen.Show();
            Assert.AreEqual(1f, canvasGroup.alpha, 0.01f);

            // Hide it
            loadingScreen.Hide();
            Assert.AreEqual(0f, canvasGroup.alpha, 0.01f);

            Object.Destroy(go);
        }
    }
}
