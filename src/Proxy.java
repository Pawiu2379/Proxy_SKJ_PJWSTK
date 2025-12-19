import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

class NodeInfo {
    String address;
    int port;
    boolean isTCP;
    boolean isUDP;
    boolean isProxy;
    Set<String> directKeys;

    public NodeInfo(String address, int port) {
        this.address = address;
        this.port = port;
        this.directKeys = new HashSet<>();
        this.isProxy = isProxy(address,port,500 );
        if (!isProxy){
            this.isTCP = isTcpPort(address, port, 500);
            this.isUDP = isUdpPort(address, port, 500);
        }else{
            this.isTCP = true;
            this.isUDP = true;
            this.directKeys = null;
        }
    }

    //    Sprawdzanie czy serwer odpowiada na tcp
    public boolean isTcpPort(String address, int port, int timeoutMs) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(address, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);

            PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
            out.println("GET NAMES");

            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            String response = in.readLine();
            if (response != null && response.startsWith("OK")) {
                return handleResponse(response);
            } else return false;
        } catch (Exception e) {
            return false;
        }
    }

    //    sprawdzanie czy serwer obsługuje UDP
    public boolean isUdpPort(String address, int port, int timeoutMs) {
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setSoTimeout(timeoutMs);

            byte[] sendData = "GET NAMES ".getBytes();
            DatagramPacket sendPacket = new DatagramPacket(sendData, sendData.length, InetAddress.getByName(address), port);
            socket.send(sendPacket);

            byte[] recvBuf = new byte[1024];
            DatagramPacket recvPacket = new DatagramPacket(recvBuf, recvBuf.length);
            socket.receive(recvPacket);

            String response = new String(recvPacket.getData(), 0, recvPacket.getLength()).trim();
            if (response.startsWith("OK")) {
                return handleResponse(response);
            } else return false;


        } catch (Exception e) {
            return false;
        }
    }

    //    sprawdzanie czy host obsługuje oba połączenia jesli tak, obstawiamy, że jest to proxy
    public boolean isProxy(String address, int port, int timeoutMs) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(address, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);

            PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
            out.println("PX HELLO");

            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            String response = in.readLine();
            return response != null && response.startsWith("PX OK");
        } catch (Exception e) {
            return false;
        }
    }

    private boolean handleResponse(String response) {
        String[] t = response.trim().split("\\s+");
        if (t.length >= 2) {
            int n = Integer.parseInt(t[1]);
            for (int i = 0; i < n && 2 + i < t.length; i++) {
                this.directKeys.add(t[2 + i]);
            }
        }
        return true;
    }
}

public class Proxy {

    private final int port;
    // znane hosty
    private final List<NodeInfo> knownNodes= new ArrayList<>();
    private final List<NodeInfo> knownProxis= new ArrayList<>();
    private final ExecutorService threadPool = Executors.newCachedThreadPool();
    private ServerSocket tcpServer;
    private DatagramSocket udpServer;


    public Proxy(int port, List<NodeInfo> nodes) {
        this.port = port;
        for (NodeInfo node : nodes){
            if (node.isProxy) {
                knownProxis.add(node);
            } else {
                knownNodes.add(node);
            }
        }
    }

    public static void main(String[] args) {
        if (args.length < 3 || !args[0].equals("-port")) {
            System.err.println("Usage: java Proxy -port <port> -server <address> <port> ...");
            System.exit(1);
        }

        int port = Integer.parseInt(args[1]);
        List<NodeInfo> nodes = new ArrayList<>();
        for (int i = 2; i < args.length; ) {
            if (args[i].equals("-server") && i + 2 < args.length) {
                String addr = args[i + 1];
                int p = Integer.parseInt(args[i + 2]);
                NodeInfo nodeInfo = new NodeInfo(addr, p);
                if (nodeInfo.isUDP || nodeInfo.isTCP) nodes.add(nodeInfo);
                i += 3;
            } else {
                i++;
            }
        }

        Proxy proxy = new Proxy(port, nodes);
        try {
            proxy.start();
        } catch (IOException e) {
            System.err.println("Proxy failed to start: " + e);
        }
    }

    private void log(String message) {
        System.out.println("Proxy:" + port + " :" + message);
        System.out.flush();
    }

    public List<String> getKnownNames() {
        List<String> names = new ArrayList<>();
        for (NodeInfo node : this.knownNodes) {
            names.addAll(node.directKeys);
        }
        for (NodeInfo p : knownProxis) {
            String resp = sendTcpCommand(p.address, p.port, "PX GET NAMES");
            // albo UDP, zależnie od p.isTCP / p.isUDP
            if (resp != null && resp.startsWith("PX OK")) {
                String[] t = resp.split("\\s+");
                int n = Integer.parseInt(t[2]);
                names.addAll(Arrays.asList(t).subList(3, n + 3));
            }
        }
        return names;
    }

    public void stop() throws IOException {
        log("Stopping...");
        if (tcpServer != null && !tcpServer.isClosed()) {
            log("Closing TCP server...");
            tcpServer.close();
        }
        if (udpServer != null && !udpServer.isClosed()) {
            log("Closing UDP server...");
            udpServer.close();
        }
        log("Shutting down thread pool...");
        threadPool.shutdownNow();
        log("Stopped.");
    }

    public void start() throws IOException {
        log("Starting... binding TCP/UDP on port " + port);
        this.tcpServer = new ServerSocket(port);
        this.udpServer = new DatagramSocket(port);
        log("Bound. Starting worker threads...");
        Thread tcpThread = new Thread(this::acceptTcpLoop, "tcp-accept");
        Thread udpThread = new Thread(this::receiveUdpLoop, "udp-recv");

        tcpThread.start();
        udpThread.start();

        for (NodeInfo n : knownNodes) {
            log("Known node " + n.address + ":" + n.port + " [TCP=" + n.isTCP + ", UDP=" + n.isUDP + "] keys=" + n.directKeys);
        }
        log("Startup complete.");
    }

    private void receiveUdpLoop() {
        byte[] buffer = new byte[1024];
        while (!udpServer.isClosed()) {
            DatagramPacket pkt = new DatagramPacket(buffer, buffer.length);
            try {
                log("UDP: waiting for datagram...");
                udpServer.receive(pkt);
                String cmd = new String(pkt.getData(), 0, pkt.getLength(), StandardCharsets.UTF_8).trim();
                log("UDP IN  <-- " + pkt.getAddress() + ":" + pkt.getPort() + " | " + cmd);

                String resp = handleCommand(new Scanner(cmd));
                log("UDP OUT --> " + pkt.getAddress() + ":" + pkt.getPort() + " | " + resp);
                byte[] out = resp.getBytes(StandardCharsets.UTF_8);
                DatagramPacket reply = new DatagramPacket(out, out.length, pkt.getAddress(), pkt.getPort());
                udpServer.send(reply);
                log("UDP OUT --> " + resp);
            } catch (SocketException se) {
                if (udpServer.isClosed()) {
                    log("UDP: server socket closed – exiting loop.");
                    break;
                }
                log("UDP: SocketException: " + se);

            } catch (IOException e) {
                log("UDP: IOException: " + e);
            }
        }
    }

    private void acceptTcpLoop() {
        while (!tcpServer.isClosed()) {
            try {
                log("TCP: waiting for client...");
                Socket clientSocket = tcpServer.accept();
                log("TCP: accepted " + clientSocket.getInetAddress() + ":" + clientSocket.getPort());
                threadPool.submit(() -> handleTcpClient(clientSocket));
            } catch (SocketException se) {
                if (tcpServer.isClosed()) break;
                log("TCP: SocketException: " + se);
            } catch (IOException e) {
                log("TCP: IOException: " + e);
            }
        }
    }

    private void handleTcpClient(Socket client) {
        try (Scanner in = new Scanner(client.getInputStream(), "UTF-8"); PrintWriter out = new PrintWriter(client.getOutputStream(), true)) {
            log("TCP: handling client " + client.getInetAddress() + ":" + client.getPort());
            String response = handleCommand(in);
            log("TCP: response -> " + response);
            out.println(response);
        } catch (IOException e) {
            log("TCP: client error: " + e);
        }
    }

    private String handleCommand(Scanner in) throws IOException {
        if (!in.hasNext()) {
            log("CMD: empty input -> NA");
            return "NA";
        }
        String param; // parametr komendy
        String command = in.next();
        StringBuilder input = new StringBuilder(command);// komenda przekazywana dalej
        String val;
        String key;
        log("CMD: command=" + command);
        StringBuilder output;//odpowiedz
        switch (command) {
            case "GET":
                if (!in.hasNext()) {
                    log("CMD GET: missing param -> NA");
                    return "NA";
                }
                param = in.next();
                input.append(" ").append(param);
                log("CMD GET: param=" + param);
                switch (param) {
                    case "NAMES":
                        LinkedHashSet<String> uniq = new LinkedHashSet<>(getKnownNames());

                        List<String> list = new ArrayList<>(uniq);
                        output = new StringBuilder("OK " + list.size() + (list.isEmpty() ? "" : " " + String.join(" ", list)));
                        log(output.toString());
                        return output.toString();
                    case "VALUE":
                        if (!in.hasNext()) {
                            log("CMD GET VALUE: missing key -> NA");
                            return "NA";
                        }
                        key = in.next();
                        input.append(" ").append(key).append(" ");
                        log("CMD GET VALUE: key=" + key);
                        for (NodeInfo n : knownNodes) {
                            if (n.directKeys.contains(key)) {
                                log("ROUTE: forwarding to " + n.address + ":" + n.port + " via " + (n.isTCP ? "TCP" : (n.isUDP ? "UDP" : "?")));
                                output = n.isTCP ? new StringBuilder(sendTcpCommand(n.address, n.port, input.toString())) : (n.isUDP ? new StringBuilder(sendUdpCommand(n.address, n.port, input.toString())) : null);
                                return (output != null) ? output.toString() : "NA";
                            }
                        }
                        log("ROUTE: no node holds key=" + key + " -> NA");
                        return "NA";
                    default:
                        log("CMD GET: unknown param=" + param + " -> NA");
                        return "NA";
                }
            case "SET":
                if (!in.hasNext()) {
                    log("CMD SET: missing key -> NA");
                    return "NA";
                }
                key = in.next();
                if (!in.hasNext()) {
                    log("CMD SET: missing value -> NA");
                    return "NA";
                }
                val = in.next();
                input.append(" ").append(key).append(" ").append(val);
                for (NodeInfo n : knownNodes) {
                    if (n.directKeys.contains(key)) {
                        log("ROUTE SET: forwarding to " + n.address + ":" + n.port + " via " + (n.isTCP ? "TCP" : (n.isUDP ? "UDP" : "?")));
                        String resp = n.isTCP ? sendTcpCommand(n.address, n.port, input.toString()) : (n.isUDP ? sendUdpCommand(n.address, n.port, input.toString()) : null);
                        log("ROUTE SET: response <- " + resp);
                        return (resp != null) ? resp : "NA";
                    }
                }
                log("ROUTE SET: no node holds key=" + key + " -> NA");
                return "NA";
            case "QUIT":
                System.out.println("Terminating");
                this.stop();
                System.exit(0);
            case "PX" :
                param = in.next();
                input = new StringBuilder(param);
                switch (param){
                    case "HELLO":
                        return "PX OK";
                    case "GET":
                        String param2 = in.next();
                        input = input.append(" ").append(param2);
                        switch(param2){
                            case "NAMES":
                                //zwracanie listy wszystkich posiadanych kluczy;
                                output = new StringBuilder("PX OK");
                                ArrayList<String> names = (ArrayList<String>) getKnownNames();
                                names = new ArrayList<>(new LinkedHashSet<>(names));
                                output.append(" ").append(names.size()).append(" ").append(String.join(" ", names));
                                return output.toString();
                            case "VALUE":
                                 key = in.next();
                                 //TODO szukanie podanego klucza w swoim drzewie
                                //odp  PX RESP <n> VALUE
                                for (NodeInfo n : knownNodes) {
                                    if (n.directKeys.contains(key)) {
                                        input.append(" ").append(key);
                                        if (n.isTCP) {
                                            output = new StringBuilder(sendTcpCommand(n.address, n.port, input.toString()));
                                        } else {
                                            output = new StringBuilder(sendUdpCommand(n.address, n.port, input.toString()));
                                        }
                                        return output.toString();
                                    }else{
                                        for(NodeInfo p : knownProxis){
                                            //TODO Przesląc do proxy
                                        }
                                    }
                                }
                        }
                    case "SET":
                        key = in.next();
                        val = in.next();
                        //TODO zmienienie klucza w podanym nodzie;

                }

            default:
                log("CMD: unknown command=" + command + " -> NA");
                return "NA";
        }
    }

    private String sendUdpCommand(String address, int port, String input) {
        log("UDP-> " + address + ":" + port + " | " + input);
        try (DatagramSocket socket = new DatagramSocket()) {
            byte[] sendData = input.getBytes();
            DatagramPacket sendPacket = new DatagramPacket(sendData, sendData.length, InetAddress.getByName(address), port);
            socket.send(sendPacket);

            byte[] recvBuf = new byte[1024];
            DatagramPacket recvPacket = new DatagramPacket(recvBuf, recvBuf.length);
            socket.setSoTimeout(1000);
            socket.receive(recvPacket);
            String resp = new String(recvPacket.getData(), 0, recvPacket.getLength()).trim();
            log("UDP<- " + address + ":" + port + " | " + resp);
            return resp;
        } catch (Exception e) {
            log("UDP x " + address + ":" + port + " | " + e);
            return "NA";
        }
    }

    private String sendTcpCommand(String address, int port, String input) {
        log("TCP-> " + address + ":" + port + " | " + input);
        try (Socket socket = new Socket(address, port); PrintWriter out = new PrintWriter(socket.getOutputStream(), true); BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))) {

            out.println(input);
            String resp = in.readLine();
            log("TCP<- " + address + ":" + port + " | " + resp);
            return resp;
        } catch (IOException e) {
            log("TCP x " + address + ":" + port + " | " + e);
            return "NA";
        }
    }

}
