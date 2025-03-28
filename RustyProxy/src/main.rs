use std::env;
use std::fs::File;
use std::io::{BufReader, Error};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;
use tokio::time::{timeout, Duration};
use tokio_rustls::TlsAcceptor;
use tokio_rustls::rustls::{Certificate, PrivateKey, ServerConfig};
use tokio_tungstenite::accept_async;

#[tokio::main]
async fn main() -> Result<(), Error> {
    let port = get_port();
    let listener = TcpListener::bind(format!("[::]:{}", port)).await?;
    println!("Servidor iniciado na porta: {}", port);

    if port == 443 {
        let tls_config = load_tls_config()?;
        let acceptor = TlsAcceptor::from(Arc::new(tls_config));
        start_secure_proxy(listener, acceptor).await;
    } else {
        start_proxy(listener).await;
    }

    Ok(())
}

async fn start_secure_proxy(listener: TcpListener, acceptor: TlsAcceptor) {
    loop {
        match listener.accept().await {
            Ok((stream, addr)) => {
                println!("Nova conexão segura de: {}", addr);
                let acceptor = acceptor.clone();
                tokio::spawn(async move {
                    match acceptor.accept(stream).await {
                        Ok(tls_stream) => {
                            match accept_async(tls_stream).await {
                                Ok(websocket) => {
                                    println!("Conexão WebSocket estabelecida com {}", addr);
                                    handle_websocket(websocket).await;
                                }
                                Err(e) => eprintln!("Erro ao aceitar WebSocket: {}", e),
                            }
                        }
                        Err(e) => eprintln!("Erro na conexão SSL: {}", e),
                    }
                });
            }
            Err(e) => eprintln!("Erro ao aceitar conexão: {}", e),
        }
    }
}

async fn start_proxy(listener: TcpListener) {
    loop {
        match listener.accept().await {
            Ok((client_stream, addr)) => {
                println!("Nova conexão de: {}", addr);
                tokio::spawn(async move {
                    if let Err(e) = handle_client(client_stream).await {
                        eprintln!("Erro ao processar cliente {}: {}", addr, e);
                    }
                });
            }
            Err(e) => eprintln!("Erro ao aceitar conexão: {}", e),
        }
    }
}

async fn handle_client(mut client_stream: TcpStream) -> Result<(), Error> {
    let status = get_status();
    client_stream.write_all(format!("HTTP/1.1 101 {}

", status).as_bytes()).await?;

    let mut buffer = [0; 1024];
    client_stream.read(&mut buffer).await?;
    client_stream.write_all(format!("HTTP/1.1 200 {}

", status).as_bytes()).await?;

    let addr_proxy = match timeout(Duration::from_secs(1), peek_stream(&mut client_stream)).await {
        Ok(Ok(data)) if data.contains("SSH") || data.is_empty() => "0.0.0.0:22",
        Ok(_) => "0.0.0.0:1194",
        Err(_) => "0.0.0.0:22",
    };

    let server_stream = match TcpStream::connect(addr_proxy).await {
        Ok(stream) => stream,
        Err(_) => {
            eprintln!("Erro ao conectar-se ao servidor proxy em {}", addr_proxy);
            return Ok(());
        }
    };

    let (client_read, client_write) = client_stream.into_split();
    let (server_read, server_write) = server_stream.into_split();

    let client_read = Arc::new(Mutex::new(client_read));
    let client_write = Arc::new(Mutex::new(client_write));
    let server_read = Arc::new(Mutex::new(server_read));
    let server_write = Arc::new(Mutex::new(server_write));

    tokio::try_join!(
        transfer_data(client_read.clone(), server_write.clone()),
        transfer_data(server_read.clone(), client_write.clone())
    )?;

    Ok(())
}

async fn handle_websocket(ws_stream: tokio_tungstenite::WebSocketStream<tokio_rustls::server::TlsStream<tokio::net::TcpStream>>) {
    println!("WebSocket conectado!");
}

async fn transfer_data(
    read_stream: Arc<Mutex<tokio::net::tcp::OwnedReadHalf>>,
    write_stream: Arc<Mutex<tokio::net::tcp::OwnedWriteHalf>>,
) -> Result<(), Error> {
    let mut buffer = [0; 8192];
    loop {
        let bytes_read = {
            let mut reader = read_stream.lock().await;
            match reader.read(&mut buffer).await {
                Ok(0) => break, 
                Ok(n) => n,
                Err(_) => break,
            }
        };

        let mut writer = write_stream.lock().await;
        if writer.write_all(&buffer[..bytes_read]).await.is_err() {
            break;
        }
    }
    Ok(())
}

async fn peek_stream(stream: &TcpStream) -> Result<String, Error> {
    let mut buffer = vec![0; 8192];
    let bytes_peeked = stream.peek(&mut buffer).await?;
    Ok(String::from_utf8_lossy(&buffer[..bytes_peeked]).to_string())
}

fn load_tls_config() -> Result<ServerConfig, Box<dyn std::error::Error>> {
    let certs = load_certs("/etc/letsencrypt/live/networlds.shop/fullchain.pem")?;
    let key = load_key("/etc/letsencrypt/live/networlds.shop/privkey.pem")?;

    let config = ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(certs, key)?;

    Ok(config)
}

fn load_certs(filename: &str) -> Result<Vec<Certificate>, Box<dyn std::error::Error>> {
    let mut reader = BufReader::new(File::open(filename)?);
    let certs = rustls_pemfile::certs(&mut reader)?
        .into_iter()
        .map(Certificate)
        .collect();
    Ok(certs)
}

fn load_key(filename: &str) -> Result<PrivateKey, Box<dyn std::error::Error>> {
    let mut reader = BufReader::new(File::open(filename)?);
    let mut keys = rustls_pemfile::pkcs8_private_keys(&mut reader)?;

    if keys.is_empty() {
        return Err("Nenhuma chave privada encontrada.".into());
    }
    Ok(PrivateKey(keys.remove(0)))
}

fn get_port() -> u16 {
    env::args().nth(2).unwrap_or_else(|| "80".to_string()).parse().unwrap_or(80)
}

fn get_status() -> String {
    env::args().nth(4).unwrap_or_else(|| "@RustyManager".to_string())
}
