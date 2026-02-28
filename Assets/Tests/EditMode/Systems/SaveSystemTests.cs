using NUnit.Framework;
using UnityEngine;

namespace BTechSimulator.Tests.EditMode
{
    /// <summary>
    /// Tests for SaveSystem and SaveData serialization.
    /// Category "Core" matches the CI shard selector.
    /// </summary>
    [TestFixture]
    [Category("Core")]
    public class SaveSystemTests
    {
        private SaveSystem _saveSystem;

        [SetUp]
        public void SetUp()
        {
            _saveSystem = new SaveSystem();
            _saveSystem.Initialize();
            _saveSystem.DeleteSave(); // clean slate
        }

        [TearDown]
        public void TearDown()
        {
            _saveSystem.DeleteSave();
        }

        [Test]
        public void HasSave_Returns_False_When_No_Save_Exists()
        {
            Assert.IsFalse(_saveSystem.HasSave());
        }

        [Test]
        public void SaveGame_Creates_File()
        {
            _saveSystem.SaveGame(new SaveData());

            Assert.IsTrue(_saveSystem.HasSave());
        }

        [Test]
        public void LoadGame_Returns_Null_When_No_Save()
        {
            var data = _saveSystem.LoadGame();
            Assert.IsNull(data);
        }

        [Test]
        public void SaveAndLoad_Roundtrip_Preserves_Data()
        {
            var original = new SaveData
            {
                playerSceneName = "Classroom",
                timeOfDay = "Afternoon",
                hasAttendedLecture = true,
                hasEatenLunch = false,
                playerPosition = new Vector3Serializable(new Vector3(1f, 2f, 3f))
            };

            _saveSystem.SaveGame(original);
            var loaded = _saveSystem.LoadGame();

            Assert.IsNotNull(loaded);
            Assert.AreEqual("Classroom", loaded.playerSceneName);
            Assert.AreEqual("Afternoon", loaded.timeOfDay);
            Assert.IsTrue(loaded.hasAttendedLecture);
            Assert.IsFalse(loaded.hasEatenLunch);
            Assert.AreEqual(1f, loaded.playerPosition.x, 0.01f);
            Assert.AreEqual(2f, loaded.playerPosition.y, 0.01f);
            Assert.AreEqual(3f, loaded.playerPosition.z, 0.01f);
        }

        [Test]
        public void DeleteSave_Removes_File()
        {
            _saveSystem.SaveGame(new SaveData());
            Assert.IsTrue(_saveSystem.HasSave());

            _saveSystem.DeleteSave();
            Assert.IsFalse(_saveSystem.HasSave());
        }

        [Test]
        public void SaveGame_Populates_Timestamp()
        {
            _saveSystem.SaveGame(new SaveData());
            var loaded = _saveSystem.LoadGame();

            Assert.IsNotNull(loaded.lastSaveTimestamp);
            Assert.IsNotEmpty(loaded.lastSaveTimestamp);
        }
    }

    /// <summary>
    /// Tests for Vector3Serializable conversion.
    /// </summary>
    [TestFixture]
    [Category("Core")]
    public class Vector3SerializableTests
    {
        [Test]
        public void Roundtrip_Conversion()
        {
            var original = new Vector3(1.5f, -2.3f, 4.7f);
            var serializable = new Vector3Serializable(original);
            var restored = serializable.ToVector3();

            Assert.AreEqual(original.x, restored.x, 0.001f);
            Assert.AreEqual(original.y, restored.y, 0.001f);
            Assert.AreEqual(original.z, restored.z, 0.001f);
        }

        [Test]
        public void Implicit_Conversion_Vector3_To_Serializable()
        {
            Vector3 original = new(3f, 6f, 9f);
            Vector3Serializable s = original;

            Assert.AreEqual(3f, s.x, 0.001f);
            Assert.AreEqual(6f, s.y, 0.001f);
            Assert.AreEqual(9f, s.z, 0.001f);
        }

        [Test]
        public void Implicit_Conversion_Serializable_To_Vector3()
        {
            var s = new Vector3Serializable { x = 1f, y = 2f, z = 3f };
            Vector3 v = s;

            Assert.AreEqual(1f, v.x, 0.001f);
            Assert.AreEqual(2f, v.y, 0.001f);
            Assert.AreEqual(3f, v.z, 0.001f);
        }
    }
}
