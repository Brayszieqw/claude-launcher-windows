using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public sealed class LoopbackFixture : IDisposable
{
    private TcpListener listener;
    private UdpClient udp;
    private Thread worker;
    private bool stopping;
    public int Port { get; private set; }
    public string LastRequest { get; private set; }
    public string Failure { get; private set; }

    public static LoopbackFixture Http(bool ipv6)
    {
        return Http(ipv6, ipv6 ? "2001:4860:4860::8888" : "8.8.8.8", 200);
    }

    public static LoopbackFixture Http(bool ipv6, string body, int status, int delayMilliseconds = 0)
    {
        var fixture = new LoopbackFixture();
        fixture.listener = new TcpListener(ipv6 ? IPAddress.IPv6Loopback : IPAddress.Loopback, 0);
        fixture.listener.Start();
        fixture.Port = ((IPEndPoint)fixture.listener.LocalEndpoint).Port;
        fixture.worker = new Thread(() =>
        {
            try
            {
                using (var client = fixture.listener.AcceptTcpClient())
                using (var stream = client.GetStream())
                {
                    stream.ReadTimeout = 5000;
                    var request = new StringBuilder();
                    while (!request.ToString().EndsWith("\r\n\r\n"))
                    {
                        int value = stream.ReadByte();
                        if (value < 0 || request.Length > 8192) throw new IOException("Incomplete request");
                        request.Append((char)value);
                    }
                    fixture.LastRequest = request.ToString().Split('\r')[0];
                    if (delayMilliseconds > 0) Thread.Sleep(delayMilliseconds);
                    byte[] response = Encoding.UTF8.GetBytes(
                        "HTTP/1.1 " + status + " Test\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: "
                        + Encoding.UTF8.GetByteCount(body) + "\r\n\r\n" + body);
                    stream.Write(response, 0, response.Length);
                }
            }
            catch (Exception error) { if (!fixture.stopping) fixture.Failure = error.Message; }
        });
        fixture.worker.IsBackground = true;
        fixture.worker.Start();
        return fixture;
    }

    public static LoopbackFixture Stun()
    {
        var fixture = new LoopbackFixture();
        fixture.udp = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
        fixture.Port = ((IPEndPoint)fixture.udp.Client.LocalEndPoint).Port;
        fixture.worker = new Thread(() =>
        {
            try
            {
                var endpoint = new IPEndPoint(IPAddress.Any, 0);
                byte[] request = fixture.udp.Receive(ref endpoint);
                if (request.Length != 20) throw new IOException("Invalid binding request");
                byte[] response = new byte[32];
                Array.Copy(request, response, 20);
                response[0] = 1; response[1] = 1; response[3] = 12;
                response[21] = 0x20; response[23] = 8; response[25] = 1;
                response[26] = 0x21; response[27] = 0x12;
                for (int i = 0; i < 4; i++) response[28+i] = (byte)(8 ^ request[4+i]);
                fixture.udp.Send(response, response.Length, endpoint);
            }
            catch (Exception error) { if (!fixture.stopping) fixture.Failure = error.Message; }
        });
        fixture.worker.IsBackground = true;
        fixture.worker.Start();
        return fixture;
    }

    public static LoopbackFixture Drip(int intervalMilliseconds, int bytes)
    {
        var fixture = new LoopbackFixture();
        fixture.listener = new TcpListener(IPAddress.Loopback, 0);
        fixture.listener.Start();
        fixture.Port = ((IPEndPoint)fixture.listener.LocalEndpoint).Port;
        fixture.worker = new Thread(() =>
        {
            try
            {
                using (var client = fixture.listener.AcceptTcpClient())
                using (var stream = client.GetStream())
                    for (int i = 0; i < bytes && !fixture.stopping; i++)
                    {
                        stream.WriteByte(65);
                        Thread.Sleep(intervalMilliseconds);
                    }
            }
            catch (IOException) { /* The deadline test closes the connection early. */ }
            catch (SocketException error) { if (!fixture.stopping) fixture.Failure = error.Message; }
        });
        fixture.worker.IsBackground = true;
        fixture.worker.Start();
        return fixture;
    }

    public void Dispose()
    {
        stopping = true;
        if (listener != null) listener.Stop();
        if (udp != null) udp.Close();
        if (worker != null) worker.Join(1000);
    }
}
