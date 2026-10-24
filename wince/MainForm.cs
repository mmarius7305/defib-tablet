// Ecranul monitor pentru Windows CE (.NET CF 3.5).
// Design pe 800x480, fullscreen. Desen ECG cu dublu buffering.

using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;
using DefibTabletCE;

namespace DefibTabletCE
{
    public class MainForm : Form
    {
        private readonly SajLinkDriver _driver;
        private readonly Timer _uiTimer = new Timer();
        private VitalsSample _lastVitals;
        private readonly Panel _ecgPanel = new Panel();
        private Bitmap _backBuffer;

        public MainForm(SajLinkDriver driver, IByteTransport transport)
        {
            _driver = driver;
            Text = "DefibTablet";
            WindowState = FormWindowState.Maximized;
            FormBorderStyle = FormBorderStyle.None;
            BackColor = Color.Black;
            ClientSize = new Size(800, 480);

            _ecgPanel.Dock = DockStyle.Fill;
            _ecgPanel.BackColor = Color.Black;
            Controls.Add(_ecgPanel);

            // Evenimentele driverului (vin din firul transportului):
            // pe CE folosiți Control.Invoke pentru acces la UI.
            driver.Vitals += delegate(object s, VitalsSample v)
            {
                try { Invoke(new Action(DoVitals), v); }
                catch (ObjectDisposedException) { }
                void DoVitals(VitalsSample vv) { _lastVitals = vv; }
            };

            transport.DataReceived += delegate(object s, byte[] data)
            {
                driver.OnBytes(data);
            };

            _uiTimer.Interval = 33; // ~30 fps
            _uiTimer.Tick += Redraw;
            _uiTimer.Enabled = true;
        }

        private void Redraw(object sender, EventArgs e)
        {
            if (_backBuffer == null ||
                _backBuffer.Size != _ecgPanel.ClientSize)
            {
                if (_backBuffer != null) _backBuffer.Dispose();
                _backBuffer = new Bitmap(_ecgPanel.ClientSize.Width, _ecgPanel.ClientSize.Height, PixelFormat.Format16bppRgb565);
            }

            using (Graphics g = Graphics.FromImage(_backBuffer))
            {
                int w = _backBuffer.Width, h = _backBuffer.Height;
                g.Clear(Color.Black);

                // Zona ECG: 60% sus. Zona vitals: 40% jos.
                int ecgH = (int)(h * 0.6);

                // Grilă (0,5 s / divizie).
                using (Pen grid = new Pen(Color.FromArgb(0, 58, 0)))
                {
                    for (float x = 0; x < w; x += (float)w / 12)
                        g.DrawLine(grid, x, 0, x, ecgH);
                    for (float y = ecgH / 8; y < ecgH; y += ecgH / 8)
                        g.DrawLine(grid, 0, y, w, y);
                }

                // Trasarea ECG: ultimele 6 secunde.
                int n = 6 * _driver.Ecg.SampleRateHz;
                float[] samples = _driver.Ecg.LastN(n);
                if (samples != null && samples.Length > 1)
                {
                    using (Pen trace = new Pen(Color.FromArgb(0, 255, 102), 2))
                    {
                        float rangeMv = 2.5f;
                        PointF prev = PointF.Empty;
                        for (int i = 0; i < samples.Length; i++)
                        {
                            float x = (float)i / (samples.Length - 1) * w;
                            float val = Math.Max(-rangeMv, Math.Min(rangeMv, samples[i]));
                            float y = ecgH / 2f - val / rangeMv * (ecgH / 2f);
                            if (i > 0) g.DrawLine(trace, prev.X, prev.Y, x, y);
                            prev = new PointF(x, y);
                        }
                    }
                }

                // Dale de semne vitale.
                using (Font big = new Font("Tahoma", 28f, FontStyle.Bold))
                using (Font small = new Font("Tahoma", 10f))
                {
                    DrawVital(g, small, big, 0, "FC", _lastVitals == null || !_lastVitals.HeartRate.HasValue ? "--" : _lastVitals.HeartRate.Value.ToString("0"), "bpm", Color.FromArgb(0, 255, 102));
                    DrawVital(g, small, big, 1, "SpO2", _lastVitals == null || !_lastVitals.Spo2.HasValue ? "--" : _lastVitals.Spo2.Value.ToString("0"), "%", Color.Cyan);
                    DrawVital(g, small, big, 2, "EtCO2", _lastVitals == null || !_lastVitals.Etco2.HasValue ? "--" : _lastVitals.Etco2.Value.ToString("0"), "mmHg", Color.Orange);
                }
            }

            using (Graphics pg = _ecgPanel.CreateGraphics())
            {
                pg.DrawImage(_backBuffer, 0, 0);
            }
        }

        private void DrawVital(Graphics g, Font small, Font big, int slot, string label, string value, string unit, Color color)
        {
            int w = ClientSize.Width / 3;
            int h = ClientSize.Height;
            int top = (int)(h * 0.6) + 6;
            int left = slot * w + 6;
            int boxW = w - 12;
            int boxH = (int)(h * 0.4) - 12;
            using (Brush b = new SolidBrush(Color.FromArgb(20, 20, 20)))
                g.FillRectangle(b, left, top, boxW, boxH);
            using (Pen p = new Pen(Color.FromArgb(60, 60, 60)))
                g.DrawRectangle(p, left, top, boxW, boxH);
            using (Brush b = new SolidBrush(color))
            {
                g.DrawString(label, small, b, left + 10, top + 4);
                g.DrawString(value, big, b, left + 10, top + 20);
                g.DrawString(unit, small, Brushes.Gray, left + 10, top + boxH - 18);
            }
        }

        protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
        {
            _uiTimer.Enabled = false;
            base.OnClosing(e);
        }
    }
}
