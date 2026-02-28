using NUnit.Framework;

namespace BTechSimulator.Tests.EditMode
{
    /// <summary>
    /// Tests for the ServiceLocator — the backbone of dependency management.
    /// Category "Core" matches the CI shard selector: -testCategory Core
    /// </summary>
    [TestFixture]
    [Category("Core")]
    public class ServiceLocatorTests
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

        [Test]
        public void Register_And_Get_Returns_Same_Instance()
        {
            var service = new GameStateManager();
            ServiceLocator.Register(service);

            var retrieved = ServiceLocator.Get<GameStateManager>();

            Assert.AreSame(service, retrieved);
        }

        [Test]
        public void Get_Unregistered_Service_Throws_InvalidOperationException()
        {
            Assert.Throws<System.InvalidOperationException>(() =>
            {
                ServiceLocator.Get<SaveSystem>();
            });
        }

        [Test]
        public void TryGet_Unregistered_Returns_False_And_Null()
        {
            bool found = ServiceLocator.TryGet<SaveSystem>(out var service);

            Assert.IsFalse(found);
            Assert.IsNull(service);
        }

        [Test]
        public void TryGet_Registered_Returns_True_And_Instance()
        {
            var original = new GameStateManager();
            ServiceLocator.Register(original);

            bool found = ServiceLocator.TryGet<GameStateManager>(out var service);

            Assert.IsTrue(found);
            Assert.AreSame(original, service);
        }

        [Test]
        public void Register_Overwrites_Previous_Registration()
        {
            var first = new GameStateManager();
            var second = new GameStateManager();

            ServiceLocator.Register(first);
            ServiceLocator.Register(second);

            var retrieved = ServiceLocator.Get<GameStateManager>();
            Assert.AreSame(second, retrieved);
        }

        [Test]
        public void Reset_Clears_All_Services()
        {
            ServiceLocator.Register(new GameStateManager());
            ServiceLocator.Reset();

            Assert.Throws<System.InvalidOperationException>(() =>
            {
                ServiceLocator.Get<GameStateManager>();
            });
        }
    }
}
