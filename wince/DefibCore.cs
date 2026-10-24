// Nucleul C# portat din core/ (Dart) pentru Windows CE / .NET CF 3.5.
// Rezultatul decodificării este identic cu cel al codec-ului Dart, verificat
// de tool/verify.dart din core/.

using System;
using System.Collections.Generic;

namespace DefibTabletCE
{
    /// <summary>Tipurile de cadre SAJLink (identice cu Dart: frames.dart).</summary>
    public static class SajFrameType
    {
        public const byte Vitals = 1;
        public const byte EcgBatch = 2;
        public const byte Event = 3;
        public const byte Command = 4;
        public const byte Ack = 5;
        public const byte Error = 6;
    }

    public class SajFrame
    {
        public byte Type;
        public byte[] Payload;
    }

    /// <summary>Codec SAJLink — aceeași formă de cadru ca în Dart.</summary>
    public class SajLinkCodec
    {
        private static readonly byte[] Magic = { 0x53, 0x4A, 0x4C, 0x31 };
        private readonly List<byte> _buf = new List<byte>(4096);

        public static ushort Crc16(byte[] data, int start, int end)
        {
            int crc = 0xFFFF;
            for (int i = start; i < end; i++)
            {
                crc ^= data[i] << 8;
                for (int b = 0; b < 8; b++)
                {
                    crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
                    crc &= 0xFFFF;
                }
            }
            return (ushort)crc;
        }

        public static byte[] Encode(byte type, byte[] payload)
        {
            byte[] frame = new byte[7 + payload.Length + 2];
            Array.Copy(Magic, 0, frame, 0, 4);
            frame[4] = type;
            frame[5] = (byte)(payload.Length & 0xFF);
            frame[6] = (byte)((payload.Length >> 8) & 0xFF);
            Array.Copy(payload, 0, frame, 7, payload.Length);
            ushort crc = Crc16(frame, 3, 7 + payload.Length);
            frame[7 + payload.Length] = (byte)(crc & 0xFF);
            frame[8 + payload.Length] = (byte)((crc >> 8) & 0xFF);
            return frame;
        }

        public void Feed(byte[] bytes) { _buf.AddRange(bytes); }

        /// <summary>Extrage următorul cadru valid; aruncă cadrele cu CRC greșit.</summary>
        public SajFrame DecodeNext()
        {
            while (true)
            {
                int magicIdx = IndexOfMagic();
                if (magicIdx < 0)
                {
                    int keep = Math.Min(3, _buf.Count);
                    if (_buf.Count > keep) _buf.RemoveRange(0, _buf.Count - keep);
                    return null;
                }
                if (magicIdx > 0) _buf.RemoveRange(0, magicIdx);
                if (_buf.Count < 9) return null;

                int len = _buf[5] | (_buf[6] << 8);
                int total = 7 + len + 2;
                if (_buf.Count < total) return null;

                var tmp = _buf.ToArray();
                int expectedCrc = _buf[7 + len] | (_buf[7 + len + 1] << 8);
                int actualCrc = Crc16(tmp, 3, 7 + len);
                if (expectedCrc != actualCrc)
                {
                    _buf.RemoveRange(0, 4);
                    continue;
                }
                var frame = new SajFrame();
                frame.Type = _buf[4];
                frame.Payload = new byte[len];
                _buf.CopyTo(7, frame.Payload, 0, len);
                _buf.RemoveRange(0, total);
                return frame;
            }
        }

        private int IndexOfMagic()
        {
            for (int i = 0; i + 3 < _buf.Count; i++)
            {
                if (_buf[i] == Magic[0] && _buf[i + 1] == Magic[1] &&
                    _buf[i + 2] == Magic[2] && _buf[i + 3] == Magic[3])
                    return i;
            }
            return -1;
        }
    }

    /// <summary>Buffer inelar ECG — port al EcgWaveform din Dart.</summary>
    public class EcgWaveform
    {
        private readonly float[] _buf;
        private int _writeIdx;
        private int _count;

        public readonly int SampleRateHz;
        public readonly int Capacity;

        public EcgWaveform(int sampleRateHz, int capacity)
        {
            SampleRateHz = sampleRateHz;
            Capacity = capacity;
            _buf = new float[capacity];
        }

        public int Count { get { return _count; } }

        public void Push(float millivolts)
        {
            _buf[_writeIdx] = millivolts;
            _writeIdx = (_writeIdx + 1) % Capacity;
            if (_count < Capacity) _count++;
        }

        public float[] LastN(int n)
        {
            n = Math.Min(n, _count);
            float[] outArr = new float[n];
            int start = (_writeIdx - n + Capacity) % Capacity;
            for (int i = 0; i < n; i++)
                outArr[i] = _buf[(start + i) % Capacity];
            return outArr;
        }

        public void Clear() { _writeIdx = 0; _count = 0; }
    }

    /// <summary>Semne vitale + evenimente — port al modelelor din Dart.</summary>
    public class VitalsSample
    {
        public DateTime Timestamp;
        public double? HeartRate;
        public double? Spo2;
        public double? Etco2;
        public double? Temperature;
    }

    public enum DefibEventType
    {
        RhythmAnalysis, ShockAdvised, ShockDelivered, ChargeStarted,
        PacingStarted, PacingStopped, ElectrodeWarning, DeviceSelfTest, Other
    }

    public class DefibEvent
    {
        public DateTime Timestamp;
        public DefibEventType Type;
        public int? EnergyJoules;
    }

    /// <summary>
    /// Interfața transportului de octeți (port serial SPP pe CE).
    /// </summary>
    public interface IByteTransport
    {
        void Send(byte[] data);
        event DataReceivedHandler DataReceived;
        void Close();
    }

    public delegate void DataReceivedHandler(byte[] data);

    /// <summary>
    /// Driver generic SAJLink — primește cadre prin transport și emite
    /// date în evenimente .NET. Pe CE se folosește cu SajLinkDriver,
    /// echivalentul SimulatorDriver din Dart (partea de generare a datelor
    /// poate rula pe un PC test din rețeaua ambulanței).
    /// </summary>
    public class SajLinkDriver
    {
        private readonly SajLinkCodec _codec = new SajLinkCodec();
        private readonly EcgWaveform _ecg;

        public SajLinkDriver(int sampleRateHz)
        {
            _ecg = new EcgWaveform(sampleRateHz, sampleRateHz * 30);
        }

        public event EventHandler<double> EcgSample;
        public event EventHandler<VitalsSample> Vitals;
        public event EventHandler<DefibEvent> DefibEventReceived;

        public EcgWaveform Ecg { get { return _ecg; } }

        public void OnBytes(byte[] bytes)
        {
            _codec.Feed(bytes);
            SajFrame f;
            while ((f = _codec.DecodeNext()) != null)
            {
                switch (f.Type)
                {
                    case SajFrameType.EcgBatch:
                        for (int p = 0; p + 4 <= f.Payload.Length; p += 4)
                        {
                            float mv = BitConverter.ToSingle(f.Payload, p);
                            _ecg.Push(mv);
                            if (EcgSample != null) EcgSample(this, mv);
                        }
                        break;
                    case SajFrameType.Vitals:
                        if (f.Payload.Length >= 20)
                        {
                            long ms = BitConverter.ToInt64(f.Payload, 0);
                            float hr = BitConverter.ToSingle(f.Payload, 8);
                            float spo2 = BitConverter.ToSingle(f.Payload, 12);
                            float etco2 = BitConverter.ToSingle(f.Payload, 16);
                            VitalsSample v = new VitalsSample();
                            v.Timestamp = new DateTime(1970, 1, 1).AddMilliseconds(ms);
                            v.HeartRate = hr < 0 ? (double?)null : hr;
                            v.Spo2 = spo2 < 0 ? (double?)null : spo2;
                            v.Etco2 = etco2 < 0 ? (double?)null : etco2;
                            if (Vitals != null) Vitals(this, v);
                        }
                        break;
                    case SajFrameType.Event:
                        if (f.Payload.Length >= 11)
                        {
                            long ms2 = BitConverter.ToInt64(f.Payload, 0);
                            byte typeIdx = f.Payload[8];
                            int energy = f.Payload[9] | (f.Payload[10] << 8);
                            DefibEvent ev = new DefibEvent();
                            ev.Timestamp = new DateTime(1970, 1, 1).AddMilliseconds(ms2);
                            ev.Type = typeIdx < 9 ? (DefibEventType)typeIdx : DefibEventType.Other;
                            ev.EnergyJoules = energy > 0 ? energy : (int?)null;
                            if (DefibEventReceived != null) DefibEventReceived(this, ev);
                        }
                        break;
                }
            }
        }
    }
}
