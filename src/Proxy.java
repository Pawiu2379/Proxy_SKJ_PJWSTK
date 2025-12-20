import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public class Proxy {

    private static final int TCP_TIMEOUT_MS = 900;
    private static final int UDP_TIMEOUT_MS = 900;
    private static final int UDP_BUF_SIZE = 8192;
    private static final boolean DEBUG = false;
    private enum Kind { UNKNOWN, SERVER, PROXY }
    private static final class Peer {
        final String host;
        final int port;

        volatile Kind kind = Kind.UNKNOWN;
        volatile boolean tcp = false;
        volatile boolean udp = false;

        final Set<String> directKeys = Collections.synchronizedSet(new LinkedHashSet<>());

        Peer(String host, int port) {
            this.host = host;
            this.port = port;
        }

        @Override
        public String toString() {
            return host + ":" + port + " [" + kind + ", tcp=" + tcp + ", udp=" + udp + ", keys=" + directKeys + "]";
        }
    }

    private final int port;

    private final CopyOnWriteArrayList<Peer> peers = new CopyOnWriteArrayList<>();
    private final ConcurrentHashMap<String, Peer> peerIndex = new ConcurrentHashMap<>();

    private final ExecutorService tcpPool = Executors.newCachedThreadPool();
    private volatile boolean running = true;

    private ServerSocket tcpServer;
    private DatagramSocket udpServer;

    public Proxy(int port, List<Peer> initialPeers) {
        this.port = port;
        for (Peer p : initialPeers) {
            addOrGetPeer(p.host, p.port);
        }
    }

    private Peer addOrGetPeer(String host, int port) {
        String key = host + ":" + port;
        Peer existing = peerIndex.get(key);
        if (existing != null) return existing;

        Peer created = new Peer(host, port);
        Peer prev = peerIndex.putIfAbsent(key, created);
        if (prev != null) return prev;

        peers.add(created);
        return created;
    }

    public static void main(String[] args) {
        try {
            Args parsed = Args.parse(args);
            Proxy p = new Proxy(parsed.port, parsed.peers);
            p.start();
        } catch (IllegalArgumentException e) {
            System.err.println("ERROR: " + e.getMessage());
            System.err.println("Usage: java Proxy -port <port> -server <address> <port> [-server <address> <port> ...]");
            System.exit(1);
        } catch (IOException e) {
            System.err.println("ERROR: cannot start proxy: " + e);
            System.exit(2);
        }
    }

    private void start() throws IOException {
        tcpServer = new ServerSocket(port);
        udpServer = new DatagramSocket(port);

        log("Started on port " + port + " (TCP+UDP). Initial peers=" + peers.size());

        for (Peer peer : peers) {
            ensurePeerClassified(peer);
        }

        Thread tTcp = new Thread(this::acceptTcpLoop, "proxy-tcp-accept");
        Thread tUdp = new Thread(this::receiveUdpLoop, "proxy-udp-recv");
        tTcp.start();
        tUdp.start();
    }


    private void acceptTcpLoop() {
        while (running) {
            try {
                Socket client = tcpServer.accept();
                tcpPool.submit(() -> handleTcpClient(client));
            } catch (SocketException se) {
                if (!running) break;
                log("TCP accept SocketException: " + se);
            } catch (IOException e) {
                if (!running) break;
                log("TCP accept IOException: " + e);
            }
        }
    }

    private void handleTcpClient(Socket client) {
        String remoteHost;
        try (Socket s = client;
             BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
             PrintWriter out = new PrintWriter(new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8), true)) {

            s.setSoTimeout(TCP_TIMEOUT_MS);
            remoteHost = s.getInetAddress().getHostAddress();

            String line = in.readLine();
            if (line == null) return;

            line = line.trim();
            if (line.isEmpty()) {
                out.println("NA");
                return;
            }

            Response r = handleLine(line, remoteHost);
            if (!r.noReply) out.println(r.text);

        } catch (SocketTimeoutException ste) {
            log("TCP client timeout: " + ste);
        } catch (IOException e) {
            log("TCP client IOException: " + e);
        }
    }

    private void receiveUdpLoop() {
        while (running) {
            try {
                byte[] buf = new byte[UDP_BUF_SIZE];
                DatagramPacket pkt = new DatagramPacket(buf, buf.length);
                udpServer.receive(pkt);

                String remoteHost = pkt.getAddress().getHostAddress();
                String line = new String(pkt.getData(), 0, pkt.getLength(), StandardCharsets.UTF_8).trim();
                if (line.isEmpty()) continue;

                Response r = handleLine(line, remoteHost);

                if (!r.noReply) {
                    byte[] out = r.text.getBytes(StandardCharsets.UTF_8);
                    DatagramPacket reply = new DatagramPacket(out, out.length, pkt.getAddress(), pkt.getPort());
                    udpServer.send(reply);
                }

            } catch (SocketException se) {
                if (!running) break;
                log("UDP SocketException: " + se);
            } catch (IOException e) {
                if (!running) break;
                log("UDP IOException: " + e);
            }
        }
    }

    private static final class Response {
        final String text;
        final boolean noReply;
        Response(String text, boolean noReply) { this.text = text; this.noReply = noReply; }
        static Response reply(String t) { return new Response(t, false); }
        static Response noReply() { return new Response("", true); }
    }

    private Response handleLine(String line, String remoteHost) {
        String[] t = splitTokens(line);
        if (t.length == 0) return Response.reply("NA");

        if ("PX".equals(t[0])) {
            return handleProxyCommand(t, remoteHost);
        } else {
            return handleClientCommand(t);
        }
    }

    private Response handleClientCommand(String[] t) {
        String cmd = t[0];

        if ("GET".equals(cmd)) {
            if (t.length < 2) return Response.reply("NA");
            String what = t[1];

            if ("NAMES".equals(what)) {
                List<String> names = collectNames(-1);
                return Response.reply("OK " + names.size() + (names.isEmpty() ? "" : " " + join(names)));
            }
            if ("VALUE".equals(what)) {
                if (t.length < 3) return Response.reply("NA");
                String key = t[2];
                String resp = routeGetValue(key, -1);
                return Response.reply(resp == null ? "NA" : resp);
            }
            return Response.reply("NA");
        }

        if ("SET".equals(cmd)) {
            if (t.length < 3) return Response.reply("NA");
            String key = t[1];
            String val = t[2];
            String resp = routeSet(key, val, -1);
            return Response.reply(resp == null ? "NA" : resp);
        }

        if ("QUIT".equals(cmd)) {
            new Thread(() -> shutdownNetwork(-1), "proxy-quit").start();
            return Response.noReply();
        }

        return Response.reply("NA");
    }

    private Response handleProxyCommand(String[] t, String remoteHost) {
        if (t.length < 2) return Response.reply("NA");
        String sub = t[1];

        if ("HELLO".equals(sub)) {
            if (t.length >= 3 && remoteHost != null) {
                int theirPort = parseIntSafe(t[2], -1);
                if (theirPort > 0 && theirPort <= 65535) {
                    Peer p = addOrGetPeer(remoteHost, theirPort);
                    p.kind = Kind.PROXY;
                    p.tcp = true;
                }
            }
            return Response.reply("PX OK");
        }

        if ("GET".equals(sub)) {
            if (t.length < 3) return Response.reply("NA");
            String what = t[2];

            if ("NAMES".equals(what)) {
                if (t.length < 4) return Response.reply("NA");
                int fromPort = parseIntSafe(t[3], -1);
                List<String> names = collectNames(fromPort);
                return Response.reply("PX OK " + names.size() + (names.isEmpty() ? "" : " " + join(names)));
            }

            if ("VALUE".equals(what)) {
                if (t.length < 5) return Response.reply("NA");
                String key = t[3];
                int fromPort = parseIntSafe(t[4], -1);
                String resp = routeGetValue(key, fromPort);
                return Response.reply(resp == null ? "NA" : resp);
            }

            return Response.reply("NA");
        }

        if ("SET".equals(sub)) {
            if (t.length < 5) return Response.reply("NA");
            String key = t[2];
            String val = t[3];
            int fromPort = parseIntSafe(t[4], -1);
            String resp = routeSet(key, val, fromPort);
            return Response.reply(resp == null ? "NA" : resp);
        }

        if ("QUIT".equals(sub)) {
            if (t.length < 3) return Response.reply("NA");
            int fromPort = parseIntSafe(t[2], -1);
            new Thread(() -> shutdownNetwork(fromPort), "proxy-px-quit").start();
            return Response.reply("PX OK");
        }

        return Response.reply("NA");
    }

    private List<String> collectNames(int fromPort) {
        LinkedHashSet<String> uniq = new LinkedHashSet<String>();

        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.kind == Kind.SERVER) {
                synchronized (p.directKeys) {
                    uniq.addAll(p.directKeys);
                }
            }
        }

        // other proxies
        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.kind != Kind.PROXY) continue;
            if (p.port == fromPort) continue;

            String resp = sendTcpCommand(p.host, p.port, "PX GET NAMES " + this.port);
            List<String> keys = parsePxOkNames(resp);
            uniq.addAll(keys);
        }

        return new ArrayList<String>(uniq);
    }

    private String routeGetValue(String key, int fromPort) {
        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.kind != Kind.SERVER) continue;

            boolean has;
            synchronized (p.directKeys) {
                has = p.directKeys.contains(key);
            }
            if (!has) continue;

            String cmd = "GET VALUE " + key;
            if (p.tcp) return safe(sendTcpCommand(p.host, p.port, cmd));
            if (p.udp) return safe(sendUdpCommand(p.host, p.port, cmd));
            return "NA";
        }

        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.kind != Kind.PROXY) continue;
            if (p.port == fromPort) continue;

            String resp = sendTcpCommand(p.host, p.port, "PX GET VALUE " + key + " " + this.port);
            if (resp != null) resp = resp.trim();
            if (resp != null && resp.startsWith("OK")) return resp;
        }

        return "NA";
    }

    private String routeSet(String key, String value, int fromPort) {
        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.kind != Kind.SERVER) continue;

            boolean has;
            synchronized (p.directKeys) {
                has = p.directKeys.contains(key);
            }
            if (!has) continue;

            String cmd = "SET " + key + " " + value;
            if (p.tcp) return safe(sendTcpCommand(p.host, p.port, cmd));
            if (p.udp) return safe(sendUdpCommand(p.host, p.port, cmd));
            return "NA";
        }

        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.kind != Kind.PROXY) continue;
            if (p.port == fromPort) continue;

            String resp = sendTcpCommand(p.host, p.port, "PX SET " + key + " " + value + " " + this.port);
            if (resp != null) resp = resp.trim();
            if ("OK".equals(resp)) return "OK";
        }

        return "NA";
    }

    private void shutdownNetwork(int fromPort) {
        if (!running) return;
        running = false;

        for (Peer p : peers) {
            ensurePeerClassified(p);
            if (p.port == fromPort) continue;

            if (p.kind == Kind.SERVER) {
                if (p.tcp) sendTcpOneWay(p.host, p.port, "QUIT");
                else if (p.udp) sendUdpOneWay(p.host, p.port, "QUIT");
            } else if (p.kind == Kind.PROXY) {
                sendTcpOneWay(p.host, p.port, "PX QUIT " + this.port);
            }
        }

        stopNow();
        System.exit(0);
    }

    private void stopNow() {
        try { if (tcpServer != null) tcpServer.close(); } catch (Exception ignored) {}
        try { if (udpServer != null) udpServer.close(); } catch (Exception ignored) {}
        tcpPool.shutdownNow();
        log("Stopped.");
    }

    private void ensurePeerClassified(Peer p) {
        if (p.kind != Kind.UNKNOWN) return;

        synchronized (p) {
            if (p.kind != Kind.UNKNOWN) return;

            // 1) try proxy
            String hello = sendTcpCommand(p.host, p.port, "PX HELLO " + this.port);
            if (hello != null && hello.trim().startsWith("PX OK")) {
                p.kind = Kind.PROXY;
                p.tcp = true;
                log("Classified as PROXY: " + p.host + ":" + p.port);
                return;
            }

            String tcpNames = sendTcpCommand(p.host, p.port, "GET NAMES");
            List<String> keysTcp = parseOkNames(tcpNames);
            if (!keysTcp.isEmpty()) {
                p.kind = Kind.SERVER;
                p.tcp = true;
                p.directKeys.clear();
                p.directKeys.addAll(keysTcp);
                log("Classified as TCP SERVER: " + p);
                return;
            }

            String udpNames = sendUdpCommand(p.host, p.port, "GET NAMES");
            List<String> keysUdp = parseOkNames(udpNames);
            if (!keysUdp.isEmpty()) {
                p.kind = Kind.SERVER;
                p.udp = true;
                p.directKeys.clear();
                p.directKeys.addAll(keysUdp);
                log("Classified as UDP SERVER: " + p);
                return;
            }

        }
    }

    private static String sendTcpCommand(String host, int port, String line) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), TCP_TIMEOUT_MS);
            socket.setSoTimeout(TCP_TIMEOUT_MS);

            PrintWriter out = new PrintWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8), true);
            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));

            out.println(line);
            String resp = in.readLine();
            return resp == null ? null : resp.trim();
        } catch (IOException e) {
            return null;
        }
    }

    private static String sendUdpCommand(String host, int port, String line) {
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setSoTimeout(UDP_TIMEOUT_MS);

            byte[] data = (line + " ").getBytes(StandardCharsets.UTF_8);
            DatagramPacket pkt = new DatagramPacket(data, data.length, InetAddress.getByName(host), port);
            socket.send(pkt);

            byte[] buf = new byte[UDP_BUF_SIZE];
            DatagramPacket resp = new DatagramPacket(buf, buf.length);
            socket.receive(resp);

            return new String(resp.getData(), 0, resp.getLength(), StandardCharsets.UTF_8).trim();
        } catch (IOException e) {
            return null;
        }
    }

    private static void sendTcpOneWay(String host, int port, String line) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), TCP_TIMEOUT_MS);
            PrintWriter out = new PrintWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8), true);
            out.println(line);
        } catch (IOException ignored) {}
    }

    private static void sendUdpOneWay(String host, int port, String line) {
        try (DatagramSocket socket = new DatagramSocket()) {
            byte[] data = (line + " ").getBytes(StandardCharsets.UTF_8);
            DatagramPacket pkt = new DatagramPacket(data, data.length, InetAddress.getByName(host), port);
            socket.send(pkt);
        } catch (IOException ignored) {}
    }

    private static String[] splitTokens(String line) {
        return line.trim().isEmpty() ? new String[0] : line.trim().split("\\s+");
    }

    private static List<String> parseOkNames(String resp) {
        if (resp == null) return Collections.emptyList();
        String[] t = splitTokens(resp);
        if (t.length < 2) return Collections.emptyList();
        if (!"OK".equals(t[0])) return Collections.emptyList();

        int n = parseIntSafe(t[1], -1);
        if (n <= 0) return Collections.emptyList();

        List<String> out = new ArrayList<String>(n);
        for (int i = 0; i < n && 2 + i < t.length; i++) out.add(t[2 + i]);
        return out;
    }

    private static List<String> parsePxOkNames(String resp) {
        if (resp == null) return Collections.emptyList();
        String[] t = splitTokens(resp);
        if (t.length < 3) return Collections.emptyList();
        if (!"PX".equals(t[0]) || !"OK".equals(t[1])) return Collections.emptyList();

        int n = parseIntSafe(t[2], -1);
        if (n < 0) return Collections.emptyList();

        List<String> out = new ArrayList<String>(Math.max(0, n));
        for (int i = 0; i < n && 3 + i < t.length; i++) out.add(t[3 + i]);
        return out;
    }

    private static int parseIntSafe(String s, int def) {
        try { return Integer.parseInt(s); }
        catch (Exception e) { return def; }
    }

    private static String join(List<String> xs) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < xs.size(); i++) {
            if (i > 0) sb.append(' ');
            sb.append(xs.get(i));
        }
        return sb.toString();
    }

    private static String safe(String s) { return s == null ? "NA" : s; }

    private static void log(String msg) {
        if (!DEBUG) return;
        System.out.println("[Proxy] " + msg);
        System.out.flush();
    }

    private static final class Args {
        final int port;
        final List<Peer> peers;

        private Args(int port, List<Peer> peers) {
            this.port = port;
            this.peers = peers;
        }

        static Args parse(String[] args) {
            if (args == null || args.length < 5) {
                throw new IllegalArgumentException("Too few arguments.");
            }
            if (!"-port".equals(args[0])) {
                throw new IllegalArgumentException("First argument must be -port");
            }
            int p = parsePort(args[1]);

            List<Peer> peers = new ArrayList<Peer>();
            int i = 2;
            while (i < args.length) {
                if (!"-server".equals(args[i])) {
                    throw new IllegalArgumentException("Unknown argument: " + args[i]);
                }
                if (i + 2 >= args.length) {
                    throw new IllegalArgumentException("Missing -server <addr> <port>");
                }
                String host = args[i + 1];
                int port = parsePort(args[i + 2]);
                peers.add(new Peer(host, port));
                i += 3;
            }

            if (peers.isEmpty()) throw new IllegalArgumentException("At least one -server is required.");
            return new Args(p, peers);
        }

        static int parsePort(String s) {
            int p = parseIntSafe(s, -1);
            if (p <= 0 || p > 65535) throw new IllegalArgumentException("Invalid port: " + s);
            return p;
        }
    }
}
