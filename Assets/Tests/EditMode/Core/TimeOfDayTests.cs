using NUnit.Framework;

namespace BTechSimulator.Tests.EditMode
{
    /// <summary>
    /// Tests for TimeOfDayManager state transitions.
    /// Category "Core" matches the CI shard selector.
    /// </summary>
    [TestFixture]
    [Category("Core")]
    public class TimeOfDayTests
    {
        [Test]
        public void Initial_State_Is_Morning()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();
            Assert.AreEqual(TimeOfDay.Morning, manager.Current);
        }

        [Test]
        public void AdvanceTime_Cycles_Through_All_Periods()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();

            manager.AdvanceTime();
            Assert.AreEqual(TimeOfDay.Afternoon, manager.Current);

            manager.AdvanceTime();
            Assert.AreEqual(TimeOfDay.Evening, manager.Current);

            manager.AdvanceTime();
            Assert.AreEqual(TimeOfDay.Night, manager.Current);

            manager.AdvanceTime();
            Assert.AreEqual(TimeOfDay.Morning, manager.Current); // wraps around
        }

        [Test]
        public void AdvanceTime_Fires_Event()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();

            TimeOfDay captured = TimeOfDay.Morning;
            manager.OnTimeChanged += t => captured = t;

            manager.AdvanceTime();

            Assert.AreEqual(TimeOfDay.Afternoon, captured);
        }

        [Test]
        public void SetTimeOfDay_Valid_String_Changes_State()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();

            manager.SetTimeOfDay("Evening");

            Assert.AreEqual(TimeOfDay.Evening, manager.Current);
        }

        [Test]
        public void SetTimeOfDay_Invalid_String_Keeps_Current()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();

            manager.SetTimeOfDay("InvalidTime");

            Assert.AreEqual(TimeOfDay.Morning, manager.Current);
        }

        [Test]
        public void SetTimeOfDay_Fires_Event_When_Changed()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();

            bool fired = false;
            manager.OnTimeChanged += _ => fired = true;

            manager.SetTimeOfDay("Night");

            Assert.IsTrue(fired);
        }

        [Test]
        public void SetTimeOfDay_Same_Value_Does_Not_Fire_Event()
        {
            var manager = new TimeOfDayManager();
            manager.Initialize();

            bool fired = false;
            manager.OnTimeChanged += _ => fired = true;

            manager.SetTimeOfDay("Morning"); // already morning

            Assert.IsFalse(fired);
        }
    }
}
