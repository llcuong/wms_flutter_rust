use axum::http::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE};
use axum::http::Method;
use axum::{
    extract::{Json, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use bb8::Pool;
use bb8_tiberius::ConnectionManager;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tiberius::{AuthMethod, Config, EncryptionLevel};
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::trace::TraceLayer;

// App State with connection pool
// App State with multiple connection pools
struct AppState {
    // Default database pool (GDWMS-dev)
    pool: Pool<ConnectionManager>,
    // LK database pool
    lk_pool: Option<Pool<ConnectionManager>>,
    // Database prefixes
    db_prefix: String,
    lk_db_prefix: Option<String>,
}

impl AppState {
    // Helper method to get the appropriate pool and prefix based on database type
    // fn get_db_config(&self, use_lk: bool) -> (&Pool<ConnectionManager>, &str) {
    //     if use_lk {
    //         if let Some(ref pool) = self.lk_pool {
    //             if let Some(ref prefix) = self.lk_db_prefix {
    //                 return (pool, prefix);
    //             }
    //         }
    //         tracing::warn!("⚠️ LK database not configured, falling back to default");
    //     }
    //     (&self.pool, &self.db_prefix)
    // }
}

/// Returns the database schema prefix, e.g. "[GDWMS-dev].[dbo]"
/// Reads DATABASE_NAME env var (default: "GDWMS")
fn get_db_prefix() -> String {
    let db_name = std::env::var("DATABASE_NAME").unwrap_or_else(|_| "GDWMS".to_string());
    format!("[{}].[dbo]", db_name)
}

/// Create multiple SQL Server connection pools
async fn create_db_pools(
) -> Result<(Pool<ConnectionManager>, Option<Pool<ConnectionManager>>), Box<dyn std::error::Error>>
{
    // Default database configuration
    let default_host = std::env::var("DATABASE_HOST").unwrap_or_else(|_| "localhost".to_string());
    let default_port: u16 = std::env::var("DATABASE_PORT")
        .unwrap_or_else(|_| "1433".to_string())
        .parse()?;
    let default_database = std::env::var("DATABASE_NAME").unwrap_or_else(|_| "GDWMS".to_string());
    let default_user = std::env::var("DATABASE_USER").unwrap_or_else(|_| "sa".to_string());
    let default_password =
        std::env::var("DATABASE_PASSWORD").expect("DATABASE_PASSWORD must be set");

    tracing::info!(
        "📦 Connecting to Default SQL Server: {}:{}/{}",
        default_host,
        default_port,
        default_database
    );

    // Configure default SQL Server connection
    let mut default_config = Config::new();
    default_config.host(&default_host);
    default_config.port(default_port);
    default_config.database(&default_database);
    default_config.authentication(AuthMethod::sql_server(&default_user, &default_password));
    default_config.encryption(EncryptionLevel::Off);
    default_config.trust_cert();

    // Create default connection manager
    let default_manager = ConnectionManager::new(default_config);

    // Build default pool
    let default_pool = Pool::builder()
        .max_size(10)
        .min_idle(Some(2))
        .build(default_manager)
        .await?;

    // Test default connection
    let conn = default_pool.get().await?;
    tracing::info!("✅ Default database connection successful!");
    drop(conn);

    // LK Database configuration (optional)
    let lk_pool = if let Ok(lk_host) = std::env::var("LK_DATABASE_HOST") {
        let lk_port: u16 = std::env::var("LK_DATABASE_PORT")
            .unwrap_or_else(|_| "1433".to_string())
            .parse()?;
        let lk_database =
            std::env::var("LK_DATABASE_NAME").unwrap_or_else(|_| "LK_GDWMS".to_string());
        let lk_user = std::env::var("LK_DATABASE_USER").unwrap_or_else(|_| default_user.clone());
        let lk_password =
            std::env::var("LK_DATABASE_PASSWORD").unwrap_or_else(|_| default_password.clone());

        tracing::info!(
            "📦 Connecting to LK SQL Server: {}:{}/{}",
            lk_host,
            lk_port,
            lk_database
        );

        let mut lk_config = Config::new();
        lk_config.host(&lk_host);
        lk_config.port(lk_port);
        lk_config.database(&lk_database);
        lk_config.authentication(AuthMethod::sql_server(&lk_user, &lk_password));
        lk_config.encryption(EncryptionLevel::Off);
        lk_config.trust_cert();

        let lk_manager = ConnectionManager::new(lk_config);

        let pool = Pool::builder()
            .max_size(5)
            .min_idle(Some(1))
            .build(lk_manager)
            .await?;

        // Test LK connection
        let conn = pool.get().await?;
        tracing::info!("✅ LK database connection successful!");
        drop(conn);

        Some(pool)
    } else {
        tracing::warn!("⚠️ LK_DATABASE_HOST not set, LK database not configured");
        None
    };

    Ok((default_pool, lk_pool))
}

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load environment variables
    dotenvy::dotenv().ok();

    // Create database connection pools
    let (pool, lk_pool) = create_db_pools()
        .await
        .expect("Failed to create database pools");

    tracing::info!("✅ Database connection pools created successfully!");

    let db_prefix = get_db_prefix();
    let lk_db_prefix = std::env::var("LK_DATABASE_NAME")
        .ok()
        .map(|db_name| format!("[{}].[dbo]", db_name));

    tracing::info!("🗄️ Using default database schema prefix: {}", db_prefix);
    if let Some(ref prefix) = lk_db_prefix {
        tracing::info!("🗄️ Using LK database schema prefix: {}", prefix);
    }

    // Shared state with multiple pools
    let state = Arc::new(AppState {
        pool,
        lk_pool,
        db_prefix,
        lk_db_prefix,
    });

    // CORS configuration - allow credentials with mirrored origin
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::mirror_request()) // Echo back the request origin
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers([AUTHORIZATION, ACCEPT, CONTENT_TYPE])
        .allow_credentials(true);

    // Build application with routes
    let app = Router::new()
        .route("/", get(root))
        .route("/health", get(health_check))
        .route("/api/v2/baskets/batch", post(handle_batch_baskets))
        .route(
            "/api/v2/baskets/stockin_batch",
            post(handle_stockin_batch_baskets),
        )
        .route(
            "/api/v2/baskets/stockout_batch",
            post(handle_stockout_batch_baskets),
        )
        .route("/api/v2/baskets/test-db", get(test_db_connection))
        .route("/wh_former/parameters", get(handle_get_parameters))
        .route("/wh_former/generate_batch", post(handle_generate_batch))
        // .route("/wh_former/bins", get(handle_get_bins))
        .route("/wh_former/area", get(handle_get_area_data))
        .route("/wh_former/bins", get(handle_get_bins))
        .route("/wh_former/machines", get(handle_get_machines))
        .route("/wh_former/stockout_forms", get(handle_get_stockout_forms))
        .route("/wh_former/save_batch", post(handle_save_batch))
        .route("/wh_former/stockin/save", post(handle_stockin_save))
        .route("/wh_former/stockout/save", post(handle_stockout_save))
        .route("/wh_former/empty_stock/save", post(handle_empty_stock_save))
        .route("/wh_former/moving/save", post(handle_former_moving_save))
        .route(
            "/wh_former/cleaning/save",
            post(handle_former_cleaning_save),
        )
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Get server configuration from environment
    let host = std::env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port: u16 = std::env::var("SERVER_PORT")
        .unwrap_or_else(|_| "3000".to_string())
        .parse()
        .expect("SERVER_PORT must be a valid port number");

    // Run the server
    let addr: SocketAddr = format!("{}:{}", host, port).parse().unwrap();
    tracing::info!("🚀 WMS Rust API Server listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

/// Handle batch baskets request for Stock In - fetches basket data from SQL Server
/// Currently identical to standard batch, but separated for future customization
async fn handle_stockin_batch_baskets(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<BatchRequest>,
) -> impl IntoResponse {
    let start = std::time::Instant::now();
    let count = payload.tag_ids.len();

    tracing::info!("📥 Received STOCK IN batch of {} tags", count);

    if count == 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(BatchResponse {
                data: vec![],
                processed_count: 0,
                success: false,
            }),
        );
    }

    // Get connection from pool
    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(BatchResponse {
                    data: vec![],
                    processed_count: 0,
                    success: false,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // Build parameterized query with IN clause
    let placeholders: Vec<String> = (1..=count).map(|i| format!("@P{}", i)).collect();
    let in_clause = placeholders.join(", ");

    let query = format!(
        r#"
        SELECT DISTINCT
            bmd.basket_no,
            bmd.basket_vendor,
            bmd.basket_capacity, 
            bmd.basket_length,
            bmd.basket_receive_date,
            bmd.basket_purchase_order,
            bmd.former_size,
            bmd.former_used_day,
            bmd.is_active,
            bd.bin
        FROM {db}.[wh_former_basket_master_data] bmd
        JOIN {db}.[wh_former_former_bin_data] bd ON bd.basket_no = bmd.basket_no
        WHERE bmd.basket_no IN ({in_clause})
        AND EXISTS (
            SELECT 1 
            FROM {db}.[wh_former_former_bin_data] fbd 
            WHERE fbd.basket_no = bmd.basket_no 
            AND (fbd.bin LIKE '%NBR%' OR fbd.bin IN ('GD', 'LK'))
            AND fbd.bin NOT IN ('X')
        )
        "#
    );

    // LOGGING: Print the full query and parameters
    tracing::info!(
        "🔍 SQL Query (StockIn): {}",
        query.replace("\n", " ").trim()
    );
    tracing::info!("📝 Params: {:?}", payload.tag_ids);

    // Build query with parameters
    let mut query_builder = tiberius::Query::new(query);
    for tag_id in &payload.tag_ids {
        query_builder.bind(tag_id.as_str());
    }

    // Execute query
    let results = match query_builder.query(&mut *conn).await {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                let mut data = Vec::new();
                for row in rows {
                    let is_active_val = row.get::<i32, _>("is_active").unwrap_or(0);
                    let status_str = if is_active_val == 1 {
                        "Active"
                    } else {
                        "Inactive"
                    };

                    let basket = BasketData {
                        tag_id: row
                            .get::<&str, _>("basket_no")
                            .unwrap_or_default()
                            .to_string(),
                        basket_vendor: row.get::<&str, _>("basket_vendor").map(|s| s.to_string()),
                        basket_capacity: row
                            .get::<i32, _>("basket_capacity")
                            .map(|v| v.to_string()),
                        basket_length: row.get::<&str, _>("basket_length").map(|s| s.to_string()),
                        basket_receive_date: row
                            .get::<NaiveDate, _>("basket_receive_date")
                            .map(|d| d.format("%Y-%m-%d").to_string()),
                        former_size: row.get::<&str, _>("former_size").map(|s| s.to_string()),
                        former_used_day: row
                            .get::<i32, _>("former_used_day")
                            .map(|v| v.to_string()),
                        basket_purchase_order: row
                            .get::<&str, _>("basket_purchase_order")
                            .map(|s| s.to_string()),
                        status: Some(status_str.to_string()),
                        bin: row.get::<&str, _>("bin").map(|s| s.to_string()),
                    };
                    data.push(basket);
                }
                data
            }
            Err(e) => {
                tracing::error!("❌ Failed to fetch results: {}", e);
                vec![]
            }
        },
        Err(e) => {
            tracing::warn!("⚠️ Query failed: {}. Ensure the table exists.", e);
            vec![]
        }
    };

    let processed_count = results.len();
    tracing::info!(
        "✅ Processed {} tags in {:?}",
        processed_count,
        start.elapsed()
    );

    (
        StatusCode::OK,
        Json(BatchResponse {
            data: results,
            processed_count,
            success: true,
        }),
    )
}

/// Handle stockout batch baskets request
async fn handle_stockout_batch_baskets(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<BatchRequest>,
) -> impl IntoResponse {
    let start = std::time::Instant::now();
    let count = payload.tag_ids.len();

    tracing::info!("📥 Received STOCK OUT batch of {} tags", count);

    if count == 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(BatchResponse {
                data: vec![],
                processed_count: 0,
                success: false,
            }),
        );
    }

    // Get connection from pool
    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(BatchResponse {
                    data: vec![],
                    processed_count: 0,
                    success: false,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // Build parameterized query with IN clause
    let placeholders: Vec<String> = (1..=count).map(|i| format!("@P{}", i)).collect();
    let in_clause = placeholders.join(", ");

    let query = format!(
        r#"
        SELECT DISTINCT
            bmd.basket_no,
            bmd.basket_vendor,
            bmd.basket_capacity,
            bmd.basket_length,
            bmd.basket_receive_date,
            bmd.former_size,
            bmd.former_used_day,
            bmd.basket_purchase_order,
            bmd.is_active,
            bd.bin
        FROM {db}.[wh_former_basket_master_data] bmd
        JOIN {db}.[wh_former_former_bin_data] bd ON bd.basket_no = bmd.basket_no
        WHERE bmd.basket_no IN ({in_clause})
        AND EXISTS (
            SELECT 1 
            FROM {db}.[wh_former_former_bin_data] fbd 
            WHERE fbd.basket_no = bmd.basket_no 
            
        )
        "#
    );

    // LOGGING: Print the full query and parameters
    tracing::info!(
        "🔍 SQL Query (StockOut): {}",
        query.replace("\n", " ").trim()
    );
    tracing::info!("📝 Params: {:?}", payload.tag_ids);

    // Build query with parameters
    let mut query_builder = tiberius::Query::new(query);
    for tag_id in &payload.tag_ids {
        query_builder.bind(tag_id.as_str());
    }

    // Execute query
    let results = match query_builder.query(&mut *conn).await {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                let mut data = Vec::new();
                for row in rows {
                    let is_active_val = row.get::<i32, _>("is_active").unwrap_or(0);
                    let status_str = if is_active_val == 1 {
                        "Active"
                    } else {
                        "Inactive"
                    };

                    let basket = BasketData {
                        tag_id: row
                            .get::<&str, _>("basket_no")
                            .unwrap_or_default()
                            .to_string(),
                        basket_vendor: row.get::<&str, _>("basket_vendor").map(|s| s.to_string()),
                        basket_capacity: row
                            .get::<i32, _>("basket_capacity")
                            .map(|v| v.to_string()),
                        basket_length: row.get::<&str, _>("basket_length").map(|s: &str| s.to_string()),
                        basket_receive_date: row
                            .get::<NaiveDate, _>("basket_receive_date")
                            .map(|d| d.format("%Y-%m-%d").to_string()),
                        former_size: row.get::<&str, _>("former_size").map(|s| s.to_string()),
                        former_used_day: row
                            .get::<i32, _>("former_used_day")
                            .map(|v| v.to_string()),
                        basket_purchase_order: row
                            .get::<&str, _>("basket_purchase_order")
                            .map(|s| s.to_string()),
                        status: Some(status_str.to_string()),
                        bin: row.get::<&str, _>("bin").map(|s| s.to_string()),
                    };
                    data.push(basket);
                }
                data
            }
            Err(e) => {
                tracing::error!("❌ Failed to fetch results: {}", e);
                vec![]
            }
        },
        Err(e) => {
            tracing::warn!("⚠️ Query failed: {}. Ensure the table exists.", e);
            vec![]
        }
    };

    let processed_count = results.len();
    tracing::info!(
        "✅ Processed {} tags in {:?}",
        processed_count,
        start.elapsed()
    );

    (
        StatusCode::OK,
        Json(BatchResponse {
            data: results,
            processed_count,
            success: true,
        }),
    )
}

// Root endpoint
async fn root() -> &'static str {
    "🚀 WMS Rust Axum Server Running - Connected to SQL Server"
}

// Health check endpoint
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "healthy",
        "service": "wms-rust-api",
        "version": "0.1.0"
    }))
}

// Test database connection
async fn test_db_connection(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.pool.get().await {
        Ok(mut conn) => {
            // Execute a simple query
            match conn.simple_query("SELECT 1 AS test").await {
                Ok(result) => {
                    let row = result.into_first_result().await.unwrap();
                    (
                        StatusCode::OK,
                        Json(serde_json::json!({
                            "status": "connected",
                            "message": "Database connection successful!",
                            "rows_returned": row.len()
                        })),
                    )
                }
                Err(e) => (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({
                        "status": "error",
                        "message": format!("Query failed: {}", e)
                    })),
                ),
            }
        }
        Err(e) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "status": "disconnected",
                "message": format!("Failed to get connection: {}", e)
            })),
        ),
    }
}

// Request and Response Structs
#[derive(Debug, Deserialize)]
struct BatchRequest {
    tag_ids: Vec<String>,
    pub bin_location: Option<String>,
    pub warehouse: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
struct BasketData {
    tag_id: String,
    basket_vendor: Option<String>,
    basket_capacity: Option<String>,
    basket_length: Option<String>,
    basket_receive_date: Option<String>,
    former_size: Option<String>,
    former_used_day: Option<String>,
    basket_purchase_order: Option<String>,
    status: Option<String>,
    bin: Option<String>,
}

#[derive(Debug, Serialize)]
struct BatchResponse {
    data: Vec<BasketData>,
    processed_count: usize,
    success: bool,
}

/// Handle batch baskets request - fetches basket data from SQL Server
async fn handle_batch_baskets(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<BatchRequest>,
) -> impl IntoResponse {
    let start = std::time::Instant::now();
    let count = payload.tag_ids.len();

    tracing::info!(
        "📥 Received batch of {} tags, with warehouse: {:?}, bin: {:?}",
        count,
        payload.warehouse,
        payload.bin_location
    );

    if count == 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(BatchResponse {
                data: vec![],
                processed_count: 0,
                success: false,
            }),
        );
    }

    // Get connection from pool
    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(BatchResponse {
                    data: vec![],
                    processed_count: 0,
                    success: false,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // Build parameterized query with IN clause
    let placeholders: Vec<String> = (1..=count).map(|i| format!("@P{}", i)).collect();
    let in_clause = placeholders.join(", ");

    // Simple query with condition string
    let query = format!(
        r#"
        SELECT 
            bmd.basket_no,
            bmd.basket_vendor,
            bmd.basket_capacity,
            bmd.basket_length,
            bmd.basket_receive_date,
            bmd.former_size,
            bmd.former_used_day,
            bmd.basket_purchase_order,
            bmd.is_active,
            bd.bin
        FROM {db}.[wh_former_basket_master_data] bmd
        JOIN {db}.[wh_former_former_bin_data] bd ON bd.basket_no = bmd.basket_no
        WHERE bmd.basket_no IN ({in_clause})
        
        "#
    );

    // LOGGING: Print the full query and parameters
    tracing::info!("🔍 SQL Query: {}", query.replace("\n", " ").trim());
    tracing::info!("📝 Params: {:?}", payload.tag_ids);

    // Build query with parameters
    let mut query_builder = tiberius::Query::new(query);
    for tag_id in &payload.tag_ids {
        query_builder.bind(tag_id.as_str());
    }

    // Execute query
    let results = match query_builder.query(&mut *conn).await {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                let mut data = Vec::new();
                for row in rows {
                    let is_active_val = row.get::<i32, _>("is_active").unwrap_or(0);
                    let status_str = if is_active_val == 1 {
                        "Active"
                    } else {
                        "Inactive"
                    };

                    let basket = BasketData {
                        tag_id: row
                            .get::<&str, _>("basket_no")
                            .unwrap_or_default()
                            .to_string(),
                        basket_vendor: row.get::<&str, _>("basket_vendor").map(|s| s.to_string()),
                        basket_capacity: row
                            .get::<i32, _>("basket_capacity")
                            .map(|v| v.to_string()),
                        basket_length: row.get::<&str, _>("basket_length").map(|s| s.to_string()),
                        basket_receive_date: row
                            .get::<NaiveDate, _>("basket_receive_date")
                            .map(|d| d.format("%Y-%m-%d").to_string()),
                        former_size: row.get::<&str, _>("former_size").map(|s| s.to_string()),
                        former_used_day: row
                            .get::<i32, _>("former_used_day")
                            .map(|v| v.to_string()),
                        basket_purchase_order: row
                            .get::<&str, _>("basket_purchase_order")
                            .map(|s| s.to_string()),
                        status: Some(status_str.to_string()),
                        bin: row.get::<&str, _>("bin").map(|s| s.to_string()),
                    };
                    data.push(basket);
                }
                data
            }
            Err(e) => {
                tracing::error!("❌ Failed to fetch results: {}", e);
                vec![]
            }
        },
        Err(e) => {
            tracing::warn!("⚠️ Query failed: {}. Ensure the table exists.", e);
            vec![]
        }
    };

    let processed_count = results.len();
    tracing::info!(
        "✅ Processed {} tags in {:?}",
        processed_count,
        start.elapsed()
    );

    (
        StatusCode::OK,
        Json(BatchResponse {
            data: results,
            processed_count,
            success: true,
        }),
    )
}

// Parameter Option structs for size, brand, type, surface dropdowns
#[derive(Debug, Serialize)]
struct ParameterOption {
    code: String,
    name: String,
}

#[derive(Debug, Serialize)]
struct ParameterResponse {
    data: Vec<ParameterOption>,
    success: bool,
}

/// Handle get parameters request
/// Supports distinct queries for different groups as requested
async fn handle_get_parameters(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let group = params.get("group").map(|s| s.as_str()).unwrap_or("size");

    tracing::info!("📥 Fetching parameters for group: {}", group);

    // Get connection from pool
    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(ParameterResponse {
                    data: vec![],
                    success: false,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // Determine query based on group
    let (query, param) = match group {
        "length" => (
            format!(
                r#"
            SELECT code, name 
            FROM {db}.[wh_former_parameter_data] 
            WHERE [group] = 'length' AND belong = 'former' AND is_active = 1
            ORDER BY id
            "#
            ),
            None,
        ),
        "vendor" | "brand" => (
            format!(
                r#"
            SELECT code, name 
            FROM {db}.[wh_former_parameter_data] 
            WHERE [group] = 'vendor' AND belong = 'former' AND is_active = 1
            ORDER BY id
            "#
            ),
            None,
        ),
        "itemno" | "itemNo" => (
            format!(
                r#"
            SELECT code, name 
            FROM {db}.[wh_former_parameter_data] 
            WHERE [group] = 'itemno' AND is_active = 1
            ORDER BY id
            "#
            ),
            None,
        ),
        _ => (
            // Default query for 'size' and others
            format!(
                r#"
            SELECT code, name 
            FROM {db}.[wh_former_parameter_data] 
            WHERE [group] = @P1 
            ORDER BY id
            "#
            ),
            Some(group),
        ),
    };

    tracing::info!("🔍 SQL Query: {}", query.replace("\n", " ").trim());
    if let Some(p) = param {
        tracing::info!("📝 Param: group = {}", p);
    }

    // Build query
    let mut query_builder = tiberius::Query::new(query);
    if let Some(p) = param {
        query_builder.bind(p);
    }

    // Execute query
    let results = match query_builder.query(&mut *conn).await {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                let mut data = Vec::new();
                for row in rows {
                    let option = ParameterOption {
                        code: row.get::<&str, _>("code").unwrap_or_default().to_string(),
                        name: row.get::<&str, _>("name").unwrap_or_default().to_string(),
                    };
                    data.push(option);
                }
                data
            }
            Err(e) => {
                tracing::error!("❌ Failed to fetch results: {}", e);
                vec![]
            }
        },
        Err(e) => {
            tracing::warn!("⚠️ Query failed: {}. Ensure the table exists.", e);
            vec![]
        }
    };

    tracing::info!(
        "✅ Found {} parameter options for group '{}'",
        results.len(),
        group
    );

    (
        StatusCode::OK,
        Json(ParameterResponse {
            data: results,
            success: true,
        }),
    )
}

// Batch Generation
#[derive(Debug, Deserialize)]
struct GenerateBatchRequest {
    item_no: String,
}

#[derive(Debug, Serialize)]
struct GenerateBatchResponse {
    batch_no: String,
    success: bool,
    message: String,
}

// Handle generate batch request
async fn handle_generate_batch(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<GenerateBatchRequest>,
) -> impl IntoResponse {
    let item_no = payload.item_no;
    tracing::info!("🔄 Generating batch for item: {}", item_no);

    // Get connection from pool
    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(GenerateBatchResponse {
                    batch_no: "".to_string(),
                    success: false,
                    message: format!("Database error: {}", e),
                }),
            );
        }
    };

    let db = &state.db_prefix;

    let query = format!(
        r#"
        UPDATE {db}.[wh_former_parameter_data]
        SET value = ISNULL(value, 0) + 1
        OUTPUT INSERTED.value
        WHERE name = @P1 AND is_active = 1
    "#
    );

    let mut query_builder = tiberius::Query::new(query);
    query_builder.bind(&item_no);

    let result = query_builder.query(&mut *conn).await;

    match result {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                if let Some(row) = rows.first() {
                    let new_value: i32 = match row.get::<&str, _>("value") {
                        Some(v) => v.parse().unwrap_or(0),
                        None => row.get("value").unwrap_or(0),
                    };
                    let batch_no = format!("{}{:04}", item_no, new_value);

                    tracing::info!("✅ Generated batch no: {}", batch_no);

                    (
                        StatusCode::OK,
                        Json(GenerateBatchResponse {
                            batch_no,
                            success: true,
                            message: "Batch generated successfully".to_string(),
                        }),
                    )
                } else {
                    tracing::warn!(
                        "⚠️ Item No not found or inactive: {}. Defaulting to 1.",
                        item_no
                    );
                    let batch_no = format!("{}{:04}", item_no, 1);
                    (
                        StatusCode::OK,
                        Json(GenerateBatchResponse {
                            batch_no,
                            success: true,
                            message: "Item No not found, defaulted to 1".to_string(),
                        }),
                    )
                }
            }
            Err(e) => {
                tracing::error!("❌ Failed to execute update: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(GenerateBatchResponse {
                        batch_no: "".to_string(),
                        success: false,
                        message: format!("Database execution error: {}", e),
                    }),
                )
            }
        },
        Err(e) => {
            tracing::error!("❌ Failed to query: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(GenerateBatchResponse {
                    batch_no: "".to_string(),
                    success: false,
                    message: format!("Query failed: {}", e),
                }),
            )
        }
    }
}
// Bin Data

#[derive(Serialize)]
struct AreaResponse {
    area_data: Vec<AreaData>,
}

#[derive(Serialize)]
struct AreaData {
    id: String,
    name: String,
    x: i32,
    y: i32,
    w: i32,
    l: i32,
    batch_no: i32,
    bins: HashMap<i32, HashMap<i32, Vec<BinItem>>>,
}

#[derive(Serialize)]
struct BinItem {
    bin_id: String,
    level: i32,
    batch: i32,
    x: i32,
    y: i32,
    w: i32,
    l: i32,
}

// Handle get bins request
async fn handle_get_area_data(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(AreaResponse { area_data: vec![] }),
            );
        }
    };

    let db = &state.db_prefix;

    // Get former areas (same logic as Django)
    let area_query = format!(
        r#"
        SELECT area_id, area_name, pos_x, pos_y, area_w, area_l
        FROM {db}.[warehouse_area] a
        JOIN {db}.[warehouse_warehouse] w ON a.warehouse_id = w.wh_code
        WHERE w.wh_former_func = 1
        AND area_id LIKE '%FM%'
        AND w.wh_code NOT LIKE '%MACH%'
    "#
    );

    let area_rows = conn
        .simple_query(area_query)
        .await
        .unwrap()
        .into_first_result()
        .await
        .unwrap();

    let mut area_data_vec = Vec::new();

    for row in area_rows {
        let area_id = row.get::<&str, _>("area_id").unwrap_or("").to_string();
        let area_name = row.get::<&str, _>("area_name").unwrap_or("").to_string();
        let area_x = row.get::<i32, _>("pos_x").unwrap_or(0);
        let area_y = row.get::<i32, _>("pos_y").unwrap_or(0);
        let area_w = row.get::<i32, _>("area_w").unwrap_or(0);
        let area_l = row.get::<i32, _>("area_l").unwrap_or(0);

        // Get bins for this area
        let bin_query = format!(
            r#"
            SELECT
                b.bin_id,
                b.bin_name,
                COUNT(u.basket_no) as batch_count
            FROM {db}.[warehouse_bin] b
            LEFT JOIN (
                SELECT fbd.bin AS bin_id, fbd.basket_no
                FROM {db}.[wh_former_former_bin_data] fbd
        
                UNION
                SELECT frbt.from_bin AS bin_id, frbaskett.basket_no
                FROM {db}.[wh_former_former_rack_bin_temp] frbt
                JOIN {db}.[wh_former_former_rack_basket_temp] frbaskett
                  ON frbaskett.rack_temp_id = frbt.rack_temp_id
            ) AS u
            ON u.bin_id = b.bin_id
            WHERE b.area_id = @P1
            GROUP BY b.bin_id, b.bin_name
            ORDER BY b.bin_id
        "#
        );

        let bin_stream = conn.query(bin_query, &[&area_id]).await.unwrap();

        let bin_rows = bin_stream.into_first_result().await.unwrap();

        let mut total_batch = 0;

        let mut rows: HashMap<i32, HashMap<i32, Vec<BinItem>>> = HashMap::new();

        let bin_w = 30;
        let bin_l = 30;
        let max_cols = if bin_w > 0 { area_w / bin_w } else { 1 };

        for bin_row in bin_rows {
            let bin_id = bin_row.get::<&str, _>("bin_id").unwrap_or("").to_string();
            let batch_count = bin_row.get::<i32, _>("batch_count").unwrap_or(0);

            total_batch += batch_count;

            // parse pattern FM-1-A
            let parts: Vec<&str> = bin_id.split('-').collect();
            if parts.len() != 3 {
                continue;
            }

            let row_num: i32 = parts[1].parse().unwrap_or(0);
            let level_char = parts[2];

            let level = if level_char == "A" { 2 } else { 1 };

            let col_index = (row_num - 1) % max_cols;
            let row_index = (row_num - 1) / max_cols;

            let mut bin_x = area_x + col_index * bin_w;
            let mut bin_y = area_y + row_index * bin_l;

            // convert to relative
            bin_x -= area_x;
            bin_y -= area_y;

            let bin_item = BinItem {
                bin_id,
                level,
                batch: batch_count,
                x: bin_x,
                y: bin_y,
                w: bin_w,
                l: bin_l,
            };

            rows.entry(row_num)
                .or_insert_with(HashMap::new)
                .entry(level)
                .or_insert_with(Vec::new)
                .push(bin_item);
        }

        area_data_vec.push(AreaData {
            id: area_id,
            name: area_name,
            x: area_x,
            y: area_y,
            w: area_w,
            l: area_l,
            batch_no: total_batch,
            bins: rows,
        });
    }

    (
        StatusCode::OK,
        Json(AreaResponse {
            area_data: area_data_vec,
        }),
    )
}

use chrono::NaiveDate;

// Machines API
#[derive(Debug, Serialize)]
struct MachineData {
    area_id: String,
    area_name: Option<String>,
}

#[derive(Debug, Serialize)]
struct MachineResponse {
    data: Vec<MachineData>,
    success: bool,
    message: String,
}

async fn handle_get_machines(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    tracing::info!("📥 Fetching machines");

    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(MachineResponse {
                    data: vec![],
                    success: false,
                    message: format!("Database connection error: {}", e),
                }),
            );
        }
    };

    let db = &state.db_prefix;

    let query = format!(
        r#"
        SELECT TOP (1000) [area_id]
            ,[area_name]
        FROM {db}.[warehouse_area]
        WHERE warehouse_id LIKE '%MACH%'
        AND area_name NOT IN ('GD', 'CLEAN')
        ORDER BY area_name
    "#
    );

    let stream = match conn.simple_query(query).await {
        Ok(s) => s,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(MachineResponse {
                    data: vec![],
                    success: false,
                    message: format!("Query execution error: {}", e),
                }),
            )
        }
    };

    match stream.into_first_result().await {
        Ok(rows) => {
            let mut data = Vec::new();
            for row in rows {
                data.push(MachineData {
                    area_id: row
                        .get::<&str, _>("area_id")
                        .unwrap_or_default()
                        .to_string(),
                    area_name: row.get::<&str, _>("area_name").map(|s| s.to_string()),
                });
            }
            tracing::info!("✅ Found {} machines", data.len());
            (
                StatusCode::OK,
                Json(MachineResponse {
                    data,
                    success: true,
                    message: "Success".to_string(),
                }),
            )
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(MachineResponse {
                data: vec![],
                success: false,
                message: format!("Query error: {}", e),
            }),
        ),
    }
}

// Stockout Forms API
#[derive(Debug, Serialize)]
struct StockoutFormData {
    id: i32,
    stockout_form: String,
    stockout_date: Option<String>,
    batch_no: Option<String>,
    former_size: Option<String>,
    stockout_total_basket: i32,
    stockout_total_former: i32,
    stockout_return_basket: i32,
    stockout_return_former: i32,
    most_batch_used_day: i32,
}

#[derive(Debug, Serialize)]
struct StockoutFormResponse {
    data: Vec<StockoutFormData>,
    success: bool,
    message: String,
}

async fn handle_get_stockout_forms(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let machine = params.get("machine").map(|s| s.as_str()).unwrap_or("");
    let line = params.get("line").map(|s| s.as_str()).unwrap_or("");

    tracing::info!(
        "📥 Fetching stockout forms for machine: {}, line: {}",
        machine,
        line
    );

    if machine.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(StockoutFormResponse {
                data: vec![],
                success: false,
                message: "Machine parameter is required".to_string(),
            }),
        );
    }

    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(StockoutFormResponse {
                    data: vec![],
                    success: false,
                    message: format!("Database connection error: {}", e),
                }),
            );
        }
    };

    let db = &state.db_prefix;

    let mut query = format!(
        r#"
        SELECT TOP (4) [id]
            ,[stockout_form]
            ,[stockout_date]
            ,[batch_no]
            ,[former_size]
            ,[stockout_total_basket]
            ,[stockout_total_former]
            ,[stockout_return_basket]
            ,[stockout_return_former]
            ,[most_batch_used_day]
        FROM {db}.[wh_former_former_stockout_form]
        WHERE stockout_to = @P1 AND is_confirmed = 0
    "#
    );

    if !line.is_empty() {
        query.push_str(" AND stockout_form LIKE @P2");
    }

    query.push_str(" ORDER BY id DESC");

    let mut query_builder = tiberius::Query::new(query);
    query_builder.bind(machine);

    if !line.is_empty() {
        let line_pattern = format!("%{}", line);
        query_builder.bind(line_pattern);
    }

    let stream = match query_builder.query(&mut *conn).await {
        Ok(s) => s,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(StockoutFormResponse {
                    data: vec![],
                    success: false,
                    message: format!("Query failed: {}", e),
                }),
            )
        }
    };

    match stream.into_first_result().await {
        Ok(rows) => {
            let mut data = Vec::new();
            for row in rows {
                let date_str = row
                    .try_get::<NaiveDate, _>("stockout_date")
                    .ok()
                    .flatten()
                    .map(|d| d.to_string())
                    .or_else(|| {
                        row.try_get::<&str, _>("stockout_date")
                            .ok()
                            .flatten()
                            .map(|s| s.to_string())
                    });

                let get_int = |col: &str| -> i32 {
                    row.try_get::<i32, _>(col)
                        .ok()
                        .flatten()
                        .or_else(|| row.try_get::<i64, _>(col).ok().flatten().map(|v| v as i32))
                        .unwrap_or(0)
                };

                data.push(StockoutFormData {
                    id: get_int("id"),
                    stockout_form: row
                        .get::<&str, _>("stockout_form")
                        .unwrap_or("")
                        .to_string(),
                    stockout_date: date_str,
                    batch_no: row.get::<&str, _>("batch_no").map(|s| s.to_string()),
                    former_size: row.get::<&str, _>("former_size").map(|s| s.to_string()),
                    stockout_total_basket: get_int("stockout_total_basket"),
                    stockout_total_former: get_int("stockout_total_former"),
                    stockout_return_basket: get_int("stockout_return_basket"),
                    stockout_return_former: get_int("stockout_return_former"),
                    most_batch_used_day: get_int("most_batch_used_day"),
                });
            }
            tracing::info!("✅ Found {} stockout forms", data.len());
            (
                StatusCode::OK,
                Json(StockoutFormResponse {
                    data,
                    success: true,
                    message: "Success".to_string(),
                }),
            )
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(StockoutFormResponse {
                data: vec![],
                success: false,
                message: format!("Query error: {}", e),
            }),
        ),
    }
}

// Batch Save Request Structs
#[derive(Debug, Deserialize)]
struct BatchSaveRequest {
    batch_no: String,
    master_info: MasterInfoData,
    racks: Vec<RackData>,
}

#[derive(Debug, Deserialize)]
struct MasterInfoData {
    former_size: String,
    former_vendor: String,
    former_type: String,
    former_surface: String,
    former_length: f32,
    former_purchase_order: i32,
    former_receive_form: String,
    former_item_no: String,
    former_used_day: i32,
    former_aql: Option<f32>,
    batch_data_date: String,
}

#[derive(Debug, Deserialize)]
struct RackData {
    items: Vec<BasketSaveData>,
}

#[derive(Debug, Deserialize)]
struct BasketSaveData {
    tag_id: String,
    quantity: i32,
    bin: String,
}

#[derive(Debug, Serialize)]
struct SaveBatchResponse {
    success: bool,
    message: String,
}

// Handle save batch
async fn handle_save_batch(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<BatchSaveRequest>,
) -> impl IntoResponse {
    tracing::info!("📥 Saving batch: {}", payload.batch_no);

    let mut conn = match state.pool.get().await {
        Ok(conn) => conn,
        Err(e) => {
            tracing::error!("❌ Failed to get database connection: {}", e);
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(SaveBatchResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // 1. Calculate totals
    let mut total_basket = 0;
    let mut total_former = 0;
    for rack in &payload.racks {
        total_basket += rack.items.len();
        for item in &rack.items {
            total_former += item.quantity;
        }
    }

    // Default values if missing
    let default_aql = 1.0;
    let aql = payload.master_info.former_aql.unwrap_or(default_aql);

    // 2. Upsert Batch Data (Former_batch_data)
    let query_batch = format!(
        r#"
        MERGE {db}.[wh_former_former_batch_data] AS target
        USING (SELECT @P1 AS batch_no) AS source
        ON (target.batch_no = source.batch_no)
        WHEN MATCHED THEN
            UPDATE SET 
                batch_total_basket = batch_total_basket + @P2,
                batch_total_former = batch_total_former + @P3,
                batch_total_basket_in_wh = batch_total_basket_in_wh + @P2,
                batch_total_former_in_wh = batch_total_former_in_wh + @P3,
                update_at = GETDATE(),
                update_by_id = 1
        WHEN NOT MATCHED THEN
            INSERT (
                batch_no, 
                former_size, 
                former_vendor, 
                former_type, 
                former_surface, 
                former_length, 
                former_purchase_order, 
                former_receive_form,
                former_item_no, 
                former_used_day, 
                former_aql, 
                batch_data_date,
                batch_total_basket,
                batch_total_former,
                batch_total_basket_in_wh,
                batch_total_former_in_wh,
                is_active,
                create_by_id,
                update_by_id,
                create_at,
                update_at
            )
            VALUES (
                @P1, @P4, @P5, @P6, @P7, @P8, @P9, @P14, @P10, @P11, @P12, @P13, 
                @P2, @P3, @P2, @P3, 1, 28, 28, GETDATE(), GETDATE()
            );
        "#
    );

    let res_batch = conn
        .execute(
            query_batch,
            &[
                &payload.batch_no,                          // P1
                &(total_basket as i32),                     // P2
                &total_former,                              // P3
                &payload.master_info.former_size,           // P4
                &payload.master_info.former_vendor,         // P5
                &payload.master_info.former_type,           // P6
                &payload.master_info.former_surface,        // P7
                &payload.master_info.former_length,         // P8
                &payload.master_info.former_purchase_order, // P9
                &payload.master_info.former_item_no,        // P10
                &payload.master_info.former_used_day,       // P11
                &aql,                                       // P12
                &payload.master_info.batch_data_date,       // P13
                &payload.master_info.former_receive_form,   // P14
            ],
        )
        .await;

    if let Err(e) = res_batch {
        tracing::error!("❌ Failed to upsert batch data: {}", e);
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(SaveBatchResponse {
                success: false,
                message: format!("Failed to save batch data: {}", e),
            }),
        );
    }

    // 3. Log Batch Data (Former_batch_data_log)
    let query_batch_log = format!(
        r#"
        INSERT INTO {db}.[wh_former_former_batch_data_log]
        (
            batch_no, batch_action_name, 
            batch_qty_merge, batch_basket_qty_merge, 
            batch_qty_total, batch_basket_qty_total, 
            batch_qty_stockin, batch_basket_qty_stockin, 
            batch_qty_split, batch_basket_qty_split, 
            batch_qty_in_wh, batch_basket_qty_in_wh, 
            batch_qty_stockout, batch_basket_qty_stockout,
            batch_change_day, is_confirmed,
            create_at, update_at
        )
        VALUES (
            @P1, 'CRTE', 
            @P2, @P3, 
            @P2, @P3, 
            @P2, @P3, 
            0, 0, 
            0, 0, 
            0, 0,
            GETDATE(), 0,
            GETDATE(), GETDATE()
        );
    "#
    );

    let _ = conn
        .execute(
            query_batch_log,
            &[&payload.batch_no, &total_former, &(total_basket as i32)],
        )
        .await;

    // 4. Loop items
    for rack in &payload.racks {
        for item in &rack.items {
            // a. Update Basket Master
            let query_basket = format!(
                r#"
                UPDATE {db}.[wh_former_basket_master_data]
                SET is_active = 1, 
                    former_used_day = @P1, 
                    former_size = @P2
                WHERE basket_no = @P3;
            "#
            );
            let _ = conn
                .execute(
                    query_basket,
                    &[
                        &payload.master_info.former_used_day,
                        &payload.master_info.former_size,
                        &item.tag_id,
                    ],
                )
                .await;

            // b. Upsert Bin Data
            let query_bin = format!(
                r#"
                MERGE {db}.[wh_former_former_bin_data] AS target
                USING (SELECT @P1 AS basket_no) AS source
                ON (target.basket_no = source.basket_no)
                WHEN MATCHED THEN
                    UPDATE SET 
                        bin = @P2, 
                        basket_former_qty = @P3, 
                        batch_no = @P4,
                        update_at = GETDATE()
                WHEN NOT MATCHED THEN
                    INSERT (basket_no, bin, basket_former_qty, batch_no, update_at)
                    VALUES (@P1, @P2, @P3, @P4, GETDATE());
            "#
            );
            let _ = conn
                .execute(
                    query_bin,
                    &[&item.tag_id, &item.bin, &item.quantity, &payload.batch_no],
                )
                .await;

            // c. Log Bin Data
            let query_bin_log = format!(
                r#"
                INSERT INTO {db}.[wh_former_former_bin_data_log]
                (batch_no, basket_no, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, 'CRTE', 'stockin', @P5, 28, GETDATE());
            "#
            );
            let _ = conn
                .execute(
                    query_bin_log,
                    &[
                        &payload.batch_no,
                        &item.tag_id,
                        &item.bin,
                        &item.quantity,
                        &payload.master_info.former_size,
                    ],
                )
                .await;
        }
    }

    tracing::info!("✅ Batch saved successfully");
    (
        StatusCode::OK,
        Json(SaveBatchResponse {
            success: true,
            message: "Batch saved successfully".to_string(),
        }),
    )
}

// ==================== STOCK IN SAVE ====================

#[derive(Debug, Deserialize)]
struct StockInSaveRequest {
    stockin_form: String,
    former_size: String,
    selected_machine: String,
    racks: Vec<StockInRack>,
}

#[derive(Debug, Deserialize)]
struct StockInRack {
    #[allow(dead_code)]
    rack_no: i32,
    bin: String,
    items: Vec<StockInItem>,
}

#[derive(Debug, Deserialize)]
struct StockInItem {
    #[allow(dead_code)]
    tag_id: String,
    basket_no: String,
    basket_former_qty: i32,
}

#[derive(Debug, Serialize)]
struct StockInSaveResponse {
    success: bool,
    message: String,
    total_baskets: Option<i32>,
    total_formers: Option<i32>,
    batch_no: Option<String>,
}

async fn handle_stockin_save(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<StockInSaveRequest>,
) -> impl IntoResponse {
    tracing::info!(
        "📦 Stock In Save request: form={}, machine={}",
        payload.stockin_form,
        payload.selected_machine
    );

    // Calculate totals
    let total_baskets: i32 = payload.racks.iter().map(|r| r.items.len() as i32).sum();
    let total_formers: i32 = payload
        .racks
        .iter()
        .flat_map(|r| r.items.iter())
        .map(|i| i.basket_former_qty)
        .sum();

    tracing::info!(
        "📊 Totals: {} baskets, {} formers",
        total_baskets,
        total_formers
    );

    // Debug log each item
    for rack in &payload.racks {
        tracing::info!("  Rack {}: bin={}", rack.rack_no, rack.bin);
        for item in &rack.items {
            tracing::info!(
                "    Item: basket_no={}, qty={}",
                item.basket_no,
                item.basket_former_qty
            );
        }
    }

    // Get connection from pool
    let mut conn = match state.pool.get().await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("❌ DB connection error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(StockInSaveResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                    total_baskets: None,
                    total_formers: None,
                    batch_no: None,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // 1. Get stockout form info (batch_no, most_batch_used_day, stockout_date)
    let (batch_no, used_day): (String, i32) = {
        let query_get_form = format!(
            r#"
            SELECT batch_no, most_batch_used_day, stockout_date
            FROM {db}.[wh_former_former_stockout_form]
            WHERE stockout_form = @P1
              AND former_size = @P2
              AND stockout_to = @P3
        "#
        );

        let stream = match conn
            .query(
                query_get_form,
                &[
                    &payload.stockin_form,
                    &payload.former_size,
                    &payload.selected_machine,
                ],
            )
            .await
        {
            Ok(s) => s,
            Err(e) => {
                tracing::error!("❌ Query error: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(StockInSaveResponse {
                        success: false,
                        message: format!("Database error: {}", e),
                        total_baskets: None,
                        total_formers: None,
                        batch_no: None,
                    }),
                );
            }
        };

        let rows: Vec<_> = stream.into_first_result().await.unwrap_or_default();
        if rows.is_empty() {
            return (
                StatusCode::BAD_REQUEST,
                Json(StockInSaveResponse {
                    success: false,
                    message: "Stockout form not found".to_string(),
                    total_baskets: None,
                    total_formers: None,
                    batch_no: None,
                }),
            );
        }

        let row = &rows[0];
        let batch: String = row.get::<&str, _>("batch_no").unwrap_or("").to_string();
        let most_used_day: i32 = row
            .try_get::<i32, _>("most_batch_used_day")
            .ok()
            .flatten()
            .unwrap_or(0);

        // Calculate used_day = most_batch_used_day + (today - stockout_date).days
        let stockout_date = row
            .try_get::<chrono::NaiveDate, _>("stockout_date")
            .ok()
            .flatten();
        let days_diff = stockout_date
            .map(|d| (chrono::Local::now().date_naive() - d).num_days() as i32)
            .unwrap_or(0);
        let calculated_used_day = most_used_day + days_diff;

        (batch, calculated_used_day)
    };

    tracing::info!("📋 Found batch_no={}, used_day={}", batch_no, used_day);

    // 2. Update stockout_form (return counts)
    let query_update_form = format!(
        r#"
        UPDATE {db}.[wh_former_former_stockout_form]
        SET stockout_return_basket = stockout_return_basket + @P1,
            stockout_return_former = stockout_return_former + @P2,
            stockin_date = CASE WHEN stockin_date IS NULL THEN GETDATE() ELSE stockin_date END
        WHERE stockout_form = @P3
          AND former_size = @P4
          AND stockout_to = @P5
    "#
    );
    let _ = conn
        .execute(
            query_update_form,
            &[
                &total_baskets,
                &total_formers,
                &payload.stockin_form,
                &payload.former_size,
                &payload.selected_machine,
            ],
        )
        .await;

    // 3. Process each rack and item
    let key = format!("KEY{}{}", payload.stockin_form, payload.former_size);

    for rack in &payload.racks {
        for item in &rack.items {
            // Skip invalid basket_no (must start with 3001, 3002, 3003)
            if !item.basket_no.starts_with("3001")
                && !item.basket_no.starts_with("3002")
                && !item.basket_no.starts_with("3003")
            {
                tracing::warn!("⚠️ Skipping invalid basket_no: {}", item.basket_no);
                continue;
            }

            // 3a. Update basket_master_data
            let query_basket = format!(
                r#"
                UPDATE {db}.[wh_former_basket_master_data]
                SET is_active = 1, 
                    former_used_day = @P1, 
                    former_size = @P2
                WHERE basket_no = @P3;
            "#
            );
            match conn
                .execute(
                    query_basket,
                    &[&used_day, &payload.former_size, &item.basket_no],
                )
                .await
            {
                Ok(result) => tracing::info!(
                    "✅ basket_master_data updated: {} rows for basket_no={}",
                    result.total(),
                    item.basket_no
                ),
                Err(e) => tracing::error!("❌ basket_master_data update failed: {}", e),
            }

            // 3b. Upsert bin_data
            let query_bin = format!(
                r#"
                MERGE {db}.[wh_former_former_bin_data] AS target
                USING (SELECT @P1 AS basket_no) AS source
                ON (target.basket_no = source.basket_no)
                WHEN MATCHED THEN
                    UPDATE SET 
                        bin = @P2, 
                        basket_former_qty = @P3, 
                        batch_no = @P4,
                        to_bin_key = '',
                        update_at = GETDATE()
                WHEN NOT MATCHED THEN
                    INSERT (basket_no, bin, basket_former_qty, batch_no, to_bin_key, update_at)
                    VALUES (@P1, @P2, @P3, @P4, '', GETDATE());
            "#
            );
            match conn
                .execute(
                    query_bin,
                    &[
                        &item.basket_no,
                        &rack.bin,
                        &item.basket_former_qty,
                        &batch_no,
                    ],
                )
                .await
            {
                Ok(result) => tracing::info!(
                    "✅ bin_data upserted: {} rows, bin={}",
                    result.total(),
                    rack.bin
                ),
                Err(e) => tracing::error!("❌ bin_data upsert failed: {}", e),
            }

            // 3c. Log bin_data
            let query_bin_log = format!(
                r#"
                INSERT INTO {db}.[wh_former_former_bin_data_log]
                (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, @P5, 'STIN', 'stockin', @P6, 28, GETDATE());
            "#
            );
            match conn
                .execute(
                    query_bin_log,
                    &[
                        &batch_no,
                        &item.basket_no,
                        &payload.selected_machine, // from_bin = machine
                        &rack.bin,                 // to_bin = rack bin
                        &item.basket_former_qty,
                        &payload.former_size,
                    ],
                )
                .await
            {
                Ok(_) => tracing::info!("✅ bin_data_log inserted"),
                Err(e) => tracing::error!("❌ bin_data_log insert failed: {}", e),
            }

            // 3d. Update rfid_read_log
            let query_rfid = format!(
                r#"
                UPDATE {db}.[wh_former_rfid_read_log]
                SET is_used = 1
                WHERE basket_no = @P1 AND is_used = 0;
            "#
            );
            match conn.execute(query_rfid, &[&item.basket_no]).await {
                Ok(result) => tracing::info!("✅ rfid_read_log updated: {} rows", result.total()),
                Err(e) => tracing::error!("❌ rfid_read_log update failed: {}", e),
            }
        }
    }

    // 4. Upsert batch_data_log
    let log_exists = {
        let query_check_log = format!(
            r#"
            SELECT COUNT(*) as cnt FROM {db}.[wh_former_former_batch_data_log]
            WHERE batch_no = @P1 AND batch_action_name = 'STIN' AND batch_sub_action_key = @P2
        "#
        );
        match conn.query(query_check_log, &[&batch_no, &key]).await {
            Ok(stream) => {
                let rows: Vec<_> = stream.into_first_result().await.unwrap_or_default();
                if let Some(row) = rows.first() {
                    row.try_get::<i32, _>("cnt").ok().flatten().unwrap_or(0) > 0
                } else {
                    false
                }
            }
            Err(_) => false,
        }
    };

    if log_exists {
        // Update existing log
        let query_update_log = format!(
            r#"
            UPDATE {db}.[wh_former_former_batch_data_log]
            SET batch_qty_in_wh = batch_qty_in_wh + @P1,
                batch_qty_stockin = batch_qty_stockin + @P1,
                batch_basket_qty_in_wh = batch_basket_qty_in_wh + @P2,
                batch_basket_qty_stockin = batch_basket_qty_stockin + @P2
            WHERE batch_no = @P3 AND batch_action_name = 'STIN' AND batch_sub_action_key = @P4
        "#
        );
        let _ = conn
            .execute(
                query_update_log,
                &[&total_formers, &total_baskets, &batch_no, &key],
            )
            .await;
    } else {
        // Insert new log with all required NOT NULL columns
        let query_insert_log = format!(
            r#"
            INSERT INTO {db}.[wh_former_former_batch_data_log]
            (batch_no, batch_action_name, batch_sub_action_key, 
             batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split, batch_qty_in_wh, batch_qty_total,
             batch_basket_qty_stockout, batch_basket_qty_stockin, batch_basket_qty_merge, batch_basket_qty_split, batch_basket_qty_in_wh, batch_basket_qty_total,
             batch_used_day, batch_change_day, create_at, update_at, is_confirmed)
            SELECT 
                @P1, 'STIN', @P2,
                0, @P3, 0, 0, batch_total_former_in_wh + @P3, batch_total_former,
                0, @P4, 0, 0, batch_total_basket_in_wh + @P4, batch_total_basket,
                @P5, GETDATE(), GETDATE(), GETDATE(), 0
            FROM {db}.[wh_former_former_batch_data] WHERE batch_no = @P1
        "#
        );
        let _ = conn
            .execute(
                query_insert_log,
                &[&batch_no, &key, &total_formers, &total_baskets, &used_day],
            )
            .await;
    }

    // 5. Update batch_data
    let query_update_batch = format!(
        r#"
        UPDATE {db}.[wh_former_former_batch_data]
        SET batch_total_basket_in_wh = batch_total_basket_in_wh + @P1,
            batch_total_former_in_wh = batch_total_former_in_wh + @P2,
            former_used_day = @P3,
            update_by_id = 28,
            update_at = GETDATE()
        WHERE batch_no = @P4
    "#
    );
    let _ = conn
        .execute(
            query_update_batch,
            &[&total_baskets, &total_formers, &used_day, &batch_no],
        )
        .await;

    tracing::info!("✅ Stock In saved successfully");
    (
        StatusCode::OK,
        Json(StockInSaveResponse {
            success: true,
            message: "Stock In saved successfully".to_string(),
            total_baskets: Some(total_baskets),
            total_formers: Some(total_formers),
            batch_no: Some(batch_no),
        }),
    )
}

// ==================== STOCK OUT SAVE ====================
#[derive(Debug, Deserialize)]
struct StockOutSaveRequest {
    stockout_form: String,
    former_size: String,
    selected_machine: String,
    stockout_from: String,
    action: String,
    racks: Vec<StockOutRack>,
}

#[derive(Debug, Deserialize)]
struct StockOutRack {
    #[allow(dead_code)]
    rack_no: i32,
    bin: String,
    items: Vec<StockOutItem>,
}

#[derive(Debug, Deserialize)]
struct StockOutItem {
    #[allow(dead_code)]
    tag_id: String,
    basket_no: String,
    basket_former_qty: i32,
}

#[derive(Debug, Serialize)]
struct StockOutSaveResponse {
    success: bool,
    message: String,
    total_baskets: Option<i32>,
    total_formers: Option<i32>,
    batch_no: Option<String>,
}

async fn handle_stockout_save(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<StockOutSaveRequest>,
) -> impl IntoResponse {
    tracing::info!(
        "📦 Stock Out Save request: form={}, machine={}, action={}",
        payload.stockout_form,
        payload.selected_machine,
        payload.action
    );

    // Calculate totals
    let total_baskets: i32 = payload.racks.iter().map(|r| r.items.len() as i32).sum();
    let total_formers: i32 = payload
        .racks
        .iter()
        .flat_map(|r| r.items.iter())
        .map(|i| i.basket_former_qty)
        .sum();

    tracing::info!(
        "📊 Totals: {} baskets, {} formers",
        total_baskets,
        total_formers
    );

    for rack in &payload.racks {
        tracing::info!("  Rack {}: bin={}", rack.rack_no, rack.bin);
        for item in &rack.items {
            tracing::info!(
                "    Item: basket_no={}, qty={}",
                item.basket_no,
                item.basket_former_qty
            );
        }
    }

    let mut conn = match state.pool.get().await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("❌ DB connection error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(StockOutSaveResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                    total_baskets: None,
                    total_formers: None,
                    batch_no: None,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // 1. Get stockout form info
    let (batch_no, used_day, is_exist): (String, i32, bool) = {
        let query_get_form = format!(
            r#"
            SELECT batch_no, most_batch_used_day
            FROM {db}.[wh_former_former_stockout_form]
            WHERE stockout_form = @P1
              AND former_size = @P2
              AND stockout_to = @P3
            "#
        );

        let rows: Vec<_> = {
            let stream = match conn
                .query(
                    query_get_form,
                    &[
                        &payload.stockout_form,
                        &payload.former_size,
                        &payload.selected_machine,
                    ],
                )
                .await
            {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!("❌ Query error: {}", e);
                    return (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(StockOutSaveResponse {
                            success: false,
                            message: "Database error".to_string(),
                            total_baskets: None,
                            total_formers: None,
                            batch_no: None,
                        }),
                    );
                }
            };
            stream.into_first_result().await.unwrap_or_default()
        };

        if let Some(row) = rows.first() {
            let batch = row.get::<&str, _>("batch_no").unwrap_or("").to_string();
            let used_day = row
                .try_get::<i32, _>("most_batch_used_day")
                .ok()
                .flatten()
                .unwrap_or(0);
            (batch, used_day, true)
        } else {
            tracing::warn!("⚠️ Stockout form not found, deriving batch...");

            let basket_nos: Vec<String> = payload
                .racks
                .iter()
                .flat_map(|r| r.items.iter())
                .map(|i| i.basket_no.clone())
                .collect();

            let placeholders: Vec<String> = (0..basket_nos.len())
                .map(|i| format!("@P{}", i + 1))
                .collect();

            let sql = format!(
                r#"
                SELECT TOP 1 batch_no, COUNT(*) as cnt
                FROM {db}.[wh_former_former_bin_data]
                WHERE basket_no IN ({})
                GROUP BY batch_no
                ORDER BY cnt DESC
                "#,
                placeholders.join(",")
            );

            let params: Vec<&dyn tiberius::ToSql> = basket_nos
                .iter()
                .map(|b| b as &dyn tiberius::ToSql)
                .collect();

            let rows: Vec<_> = {
                let stream = conn.query(&sql, &params).await.unwrap();
                stream.into_first_result().await.unwrap_or_default()
            };

            if rows.is_empty() {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(StockOutSaveResponse {
                        success: false,
                        message: "Cannot determine batch from baskets".to_string(),
                        total_baskets: None,
                        total_formers: None,
                        batch_no: None,
                    }),
                );
            }

            let derived_batch = rows[0].get::<&str, _>("batch_no").unwrap().to_string();

            let base_used_day: i32 = {
                let query_batch = format!(
                    r#"
                    SELECT former_used_day
                    FROM {db}.[wh_former_former_batch_data]
                    WHERE batch_no = @P1
                    "#
                );
                let stream = conn.query(query_batch, &[&derived_batch]).await.unwrap();
                let rows: Vec<_> = stream.into_first_result().await.unwrap_or_default();
                rows.get(0)
                    .and_then(|r| r.try_get::<i32, _>("former_used_day").ok().flatten())
                    .unwrap_or(0)
            };

            (derived_batch, base_used_day, false)
        }
    };

    tracing::info!(
        "📋 batch_no={}, used_day={}, exists={}",
        batch_no,
        used_day,
        is_exist
    );

    let most_batch_former_qty = total_formers;

    // 2. UPSERT stockout_form
    if is_exist {
        let update_sql = format!(
            r#"
            UPDATE {db}.[wh_former_former_stockout_form]
            SET stockout_date = GETDATE(),
                stockout_action = @P8,
                stockout_to = @P7,
                stockout_from = @P11,
                batch_no = @P9,
                former_size = @P10,
                stockout_total_basket = stockout_total_basket + @P1,
                stockout_total_former = stockout_total_former + @P2,
                most_batch_former_qty = @P3,
                most_batch_used_day = @P4
            WHERE stockout_form = @P5
            "#
        );
        let _ = conn
            .execute(
                update_sql,
                &[
                    &total_baskets,
                    &total_formers,
                    &most_batch_former_qty,
                    &used_day,
                    &payload.stockout_form,
                    &payload.former_size,
                    &payload.selected_machine,
                    &payload.action,
                    &batch_no,
                    &payload.former_size,
                    &payload.stockout_from,
                ],
            )
            .await;
    } else {
        let insert_sql = format!(
            r#"
            INSERT INTO {db}.[wh_former_former_stockout_form] (
                stockout_form, stockout_date, stockout_action, stockout_to, stockout_from,
                batch_no, former_size, stockout_total_basket, stockout_total_former,
                stockout_return_basket, stockout_return_former,
                most_batch_former_qty, most_batch_used_day, is_closed, is_confirmed
            )
            SELECT 
                @P1, GETDATE(), @P2, 'LK', @P3, 
                @P4, b.former_size, @P5, @P6, 0, 0, @P7, @P8, 0, 0
            FROM {db}.[wh_former_former_batch_data] b
            WHERE b.batch_no = @P4
            "#
        );

        let result = conn
            .execute(
                insert_sql,
                &[
                    &payload.stockout_form, // P1
                    &payload.action,        // P2
                    &payload.stockout_from, // P3
                    &batch_no,              // P4
                    &total_baskets,         // P5
                    &total_formers,         // P6
                    &most_batch_former_qty, // P7
                    &used_day,              // P8
                ],
            )
            .await;

        match result {
            Ok(rows_affected) => {
                if rows_affected.total() == 0 {
                    tracing::warn!("⚠️ Batch {} not found, insert failed", batch_no);
                    return (
                        StatusCode::BAD_REQUEST,
                        Json(StockOutSaveResponse {
                            success: false,
                            message: format!("Batch {} not found", batch_no),
                            total_baskets: Some(total_baskets),
                            total_formers: Some(total_formers),
                            batch_no: Some(batch_no),
                        }),
                    );
                }
            }
            Err(e) => {
                tracing::error!("❌ Failed to insert stockout form: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(StockOutSaveResponse {
                        success: false,
                        message: format!("Failed to insert stockout form: {}", e),
                        total_baskets: None,
                        total_formers: None,
                        batch_no: None,
                    }),
                );
            }
        }
    }

    // 3. Process each rack and item
    let key = format!("KEY{}{}", payload.stockout_form, payload.former_size);

    for rack in &payload.racks {
        for item in &rack.items {
            if !item.basket_no.starts_with("3001")
                && !item.basket_no.starts_with("3002")
                && !item.basket_no.starts_with("3003")
            {
                tracing::warn!("⚠️ Skipping invalid basket_no: {}", item.basket_no);
                continue;
            }

            // 3a. Update basket_master_data
            let query_basket = format!(
                r#"
                UPDATE {db}.[wh_former_basket_master_data]
                SET is_active = 1,
                    former_used_day = @P1,
                    former_size = @P2
                WHERE basket_no = @P3;
                "#
            );
            match conn
                .execute(
                    &query_basket,
                    &[&used_day, &payload.former_size, &item.basket_no],
                )
                .await
            {
                Ok(result) => tracing::info!(
                    "✅ basket_master_data updated: {} rows for basket_no={}",
                    result.total(),
                    item.basket_no
                ),
                Err(e) => tracing::error!("❌ basket_master_data update failed: {}", e),
            }

            // 3b. Upsert bin_data
            let query_bin = format!(
                r#"
                MERGE {db}.[wh_former_former_bin_data] AS target
                USING (SELECT @P1 AS basket_no) AS source
                ON (target.basket_no = source.basket_no)
                WHEN MATCHED THEN
                    UPDATE SET bin = @P2, basket_former_qty = @P3, batch_no = @P4,
                               to_bin_key = '', update_at = GETDATE()
                WHEN NOT MATCHED THEN
                    INSERT (basket_no, bin, basket_former_qty, batch_no, to_bin_key, update_at)
                    VALUES (@P1, @P2, @P3, @P4, '', GETDATE());
                "#
            );
            match conn
                .execute(
                    &query_bin,
                    &[
                        &item.basket_no,
                        &payload.selected_machine,
                        &item.basket_former_qty,
                        &batch_no,
                    ],
                )
                .await
            {
                Ok(result) => tracing::info!(
                    "✅ bin_data upserted: {} rows, bin={}",
                    result.total(),
                    rack.bin
                ),
                Err(e) => tracing::error!("❌ bin_data upsert failed: {}", e),
            }

            // 3c. Log bin_data
            let query_bin_log = format!(
                r#"
                INSERT INTO {db}.[wh_former_former_bin_data_log]
                (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, @P5, 'STIN', 'stockin', @P6, 28, GETDATE());
                "#
            );
            match conn
                .execute(
                    &query_bin_log,
                    &[
                        &batch_no,
                        &item.basket_no,
                        &rack.bin,
                        &payload.selected_machine,
                        &item.basket_former_qty,
                        &payload.former_size,
                    ],
                )
                .await
            {
                Ok(_) => tracing::info!("✅ bin_data_log inserted"),
                Err(e) => tracing::error!("❌ bin_data_log insert failed: {}", e),
            }

            // 3d. Update rfid_read_log
            let query_rfid = format!(
                r#"
                UPDATE {db}.[wh_former_rfid_read_log]
                SET is_used = 1
                WHERE basket_no = @P1 AND is_used = 0;
                "#
            );
            match conn.execute(&query_rfid, &[&item.basket_no]).await {
                Ok(result) => tracing::info!("✅ rfid_read_log updated: {} rows", result.total()),
                Err(e) => tracing::error!("❌ rfid_read_log update failed: {}", e),
            }
        }
    }

    // 4. Upsert batch_data_log
    let log_exists = {
        let query_check_log = format!(
            r#"
            SELECT COUNT(*) as cnt FROM {db}.[wh_former_former_batch_data_log]
            WHERE batch_no = @P1 AND batch_action_name = 'STOU' AND batch_sub_action_key = @P2
            "#
        );
        match conn.query(query_check_log, &[&batch_no, &key]).await {
            Ok(stream) => {
                let rows: Vec<_> = stream.into_first_result().await.unwrap_or_default();
                if let Some(row) = rows.first() {
                    row.try_get::<i32, _>("cnt").ok().flatten().unwrap_or(0) > 0
                } else {
                    false
                }
            }
            Err(_) => false,
        }
    };

    if log_exists {
        let query_update_log = format!(
            r#"
            UPDATE {db}.[wh_former_former_batch_data_log]
            SET batch_qty_in_wh = batch_qty_in_wh - @P1,
                batch_change_day = GETDATE(),
                batch_stockout_to = @P5,
                batch_qty_stockout = batch_qty_stockout + @P1,
                batch_basket_qty_in_wh = batch_basket_qty_in_wh - @P2,
                batch_basket_qty_stockout = batch_basket_qty_stockout + @P2
            WHERE batch_no = @P3 AND batch_action_name = 'STOU' AND batch_sub_action_key = @P4
            "#
        );
        let _ = conn
            .execute(
                query_update_log,
                &[
                    &total_formers,
                    &total_baskets,
                    &batch_no,
                    &key,
                    &payload.selected_machine,
                ],
            )
            .await;
    } else {
        let query_insert_log = format!(
            r#"
            INSERT INTO {db}.[wh_former_former_batch_data_log]
            (batch_no, batch_action_name, batch_sub_action_key,
             batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split, batch_qty_in_wh, batch_qty_total,
             batch_basket_qty_stockout, batch_basket_qty_stockin, batch_basket_qty_merge, batch_basket_qty_split, batch_basket_qty_in_wh, batch_basket_qty_total,
             batch_used_day, batch_change_day, create_at, update_at, is_confirmed, batch_stockout_to)
            SELECT
                @P1, 'STOU', @P2,
                @P3, 0, 0, 0, batch_total_former_in_wh - @P3, batch_total_former,
                @P4, 0, 0, 0, batch_total_basket_in_wh - @P4, batch_total_basket,
                @P5, GETDATE(), GETDATE(), GETDATE(), 0, @P6
            FROM {db}.[wh_former_former_batch_data] WHERE batch_no = @P1
            "#
        );
        let _ = conn
            .execute(
                query_insert_log,
                &[
                    &batch_no,
                    &key,
                    &total_formers,
                    &total_baskets,
                    &used_day,
                    &payload.selected_machine,
                ],
            )
            .await;
    }

    // 5. Update batch_data
    let query_update_batch = format!(
        r#"
        UPDATE {db}.[wh_former_former_batch_data]
        SET batch_total_basket_in_wh = batch_total_basket_in_wh - @P1,
            batch_total_former_in_wh = batch_total_former_in_wh - @P2,
            former_used_day = @P3,
            update_by_id = 28,
            update_at = GETDATE()
        WHERE batch_no = @P4
        "#
    );
    let _ = conn
        .execute(
            &query_update_batch,
            &[&total_baskets, &total_formers, &used_day, &batch_no],
        )
        .await;

    // ==================== GENERAL TRANSIT SECTION ====================
    let is_transit = payload.action == "toLK" || payload.action == "toGD";

    if is_transit {
        let to_lk = payload.action == "toLK";

        tracing::info!(
            "🚚 Transit action={}: starting cross-factory sync...",
            payload.action
        );

        let (lk_pool_ref, lk_db_ref) = match (&state.lk_pool, &state.lk_db_prefix) {
            (Some(pool), Some(db_prefix)) => (pool, db_prefix.clone()),
            _ => {
                tracing::error!("❌ LK pool/db_prefix not configured — skipping transit sync");
                return (
                    StatusCode::OK,
                    Json(StockOutSaveResponse {
                        success: true,
                        message: "Stock Out saved, but transit sync skipped: LK not configured"
                            .to_string(),
                        total_baskets: Some(total_baskets),
                        total_formers: Some(total_formers),
                        batch_no: Some(batch_no),
                    }),
                );
            }
        };

        let mut lk_conn = match lk_pool_ref.get().await {
            Ok(c) => c,
            Err(e) => {
                tracing::error!("❌ LK DB connection error: {}", e);
                return (
                    StatusCode::OK,
                    Json(StockOutSaveResponse {
                        success: true,
                        message: format!(
                            "Stock Out saved, but transit sync failed (connection): {}",
                            e
                        ),
                        total_baskets: Some(total_baskets),
                        total_formers: Some(total_formers),
                        batch_no: Some(batch_no),
                    }),
                );
            }
        };

        let (src_db, dst_db) = if to_lk {
            (db.clone(), lk_db_ref.clone())
        } else {
            (lk_db_ref.clone(), db.clone())
        };

        let dst_active: i32 = 4;
        let src_active: i32 = 5;

        let transit_log_action = if to_lk { "TO_LK" } else { "TO_GD" };

        // ── Step 1: Fetch batch info from the SOURCE db ──────────────────
        let query_get_batch = format!(
            r#"
            SELECT group_batch, former_receive_form, former_size, former_vendor,
                former_type, former_purchase_order, former_surface, former_length,
                former_used_day, former_item_no, former_aql, is_active,
                batch_data_date,
                batch_total_basket, batch_total_basket_in_wh,
                batch_total_former,  batch_total_former_in_wh,
                create_at
            FROM {src_db}.[wh_former_former_batch_data]
            WHERE batch_no = @P1
            "#
        );

        let batch_rows = match conn.query(&query_get_batch, &[&batch_no]).await {
            Ok(s) => s.into_first_result().await.unwrap_or_default(),
            Err(e) => {
                tracing::error!("❌ Failed to fetch batch {} from source: {}", batch_no, e);
                vec![]
            }
        };

        if let Some(brow) = batch_rows.first() {
            let group_batch = brow.get::<&str, _>("group_batch").unwrap_or("").to_string();
            let former_receive_form = brow
                .get::<&str, _>("former_receive_form")
                .unwrap_or("")
                .to_string();
            let former_size_b = brow.get::<&str, _>("former_size").unwrap_or("").to_string();
            let former_vendor = brow
                .get::<&str, _>("former_vendor")
                .unwrap_or("")
                .to_string();
            let former_type = brow.get::<&str, _>("former_type").unwrap_or("").to_string();
            let former_purchase_order = brow
                .get::<&str, _>("former_purchase_order")
                .unwrap_or("")
                .to_string();
            let former_surface = brow
                .get::<&str, _>("former_surface")
                .unwrap_or("")
                .to_string();
            let former_length = brow
                .try_get::<f64, _>("former_length")
                .ok()
                .flatten()
                .unwrap_or(0.0);
            let former_used_day_b = brow
                .try_get::<i32, _>("former_used_day")
                .ok()
                .flatten()
                .unwrap_or(0);
            let former_item_no = brow
                .get::<&str, _>("former_item_no")
                .unwrap_or("")
                .to_string();
            let former_aql = brow
                .try_get::<f64, _>("former_aql")
                .ok()
                .flatten()
                .unwrap_or(0.0);
            let is_active_b = brow
                .try_get::<i32, _>("is_active")
                .ok()
                .flatten()
                .unwrap_or(0);
            let batch_data_date: Option<chrono::NaiveDate> =
                brow.try_get("batch_data_date").ok().flatten();
            let batch_total_basket = brow
                .try_get::<i32, _>("batch_total_basket")
                .ok()
                .flatten()
                .unwrap_or(0);
            let batch_total_former = brow
                .try_get::<i32, _>("batch_total_former")
                .ok()
                .flatten()
                .unwrap_or(0);

            // ── Step 2: MERGE batch into DESTINATION db ───────────────────
            let query_dst_batch = format!(
                r#"
                MERGE {dst_db}.[wh_former_former_batch_data] AS target
                USING (SELECT @P1 AS batch_no) AS source
                ON (target.batch_no = source.batch_no)
                WHEN MATCHED THEN
                    UPDATE SET
                        group_batch           = @P2,
                        former_receive_form   = @P3,
                        former_size           = @P4,
                        former_vendor         = @P5,
                        former_type           = @P6,
                        former_purchase_order = @P7,
                        former_surface        = @P8,
                        former_length         = @P9,
                        former_used_day       = @P10,
                        former_item_no        = @P11,
                        former_aql            = @P12,
                        is_active             = @P13,
                        batch_data_date       = @P14,
                        batch_total_basket    = @P15,
                        batch_total_basket_in_wh  = batch_total_basket_in_wh + @P16,
                        batch_total_former    = @P17,
                        batch_total_former_in_wh  = batch_total_former_in_wh + @P18,
                        update_by_id = 33,
                        update_at    = GETDATE()
                WHEN NOT MATCHED THEN
                    INSERT (
                        batch_no, group_batch, former_receive_form, former_size,
                        former_vendor, former_type, former_purchase_order, former_surface,
                        former_length, former_used_day, former_item_no, former_aql,
                        is_active, batch_data_date,
                        batch_total_basket, batch_total_basket_in_wh,
                        batch_total_former,  batch_total_former_in_wh,
                        create_by_id, create_at, update_by_id, update_at
                    )
                    VALUES (
                        @P1, @P2, @P3, @P4, @P5, @P6, @P7, @P8, @P9, @P10,
                        @P11, @P12, @P13, @P14,
                        @P15, @P16, @P17, @P18,
                        33, GETDATE(), 33, GETDATE()
                    );
                "#
            );

            let dst_batch_result = if to_lk {
                lk_conn
                    .execute(
                        &query_dst_batch,
                        &[
                            &batch_no,
                            &group_batch,
                            &former_receive_form,
                            &former_size_b,
                            &former_vendor,
                            &former_type,
                            &former_purchase_order,
                            &former_surface,
                            &former_length,
                            &former_used_day_b,
                            &former_item_no,
                            &former_aql,
                            &is_active_b,
                            &batch_data_date,
                            &batch_total_basket,
                            &total_baskets,
                            &batch_total_former,
                            &total_formers,
                        ],
                    )
                    .await
            } else {
                conn.execute(
                    &query_dst_batch,
                    &[
                        &batch_no,
                        &group_batch,
                        &former_receive_form,
                        &former_size_b,
                        &former_vendor,
                        &former_type,
                        &former_purchase_order,
                        &former_surface,
                        &former_length,
                        &former_used_day_b,
                        &former_item_no,
                        &former_aql,
                        &is_active_b,
                        &batch_data_date,
                        &batch_total_basket,
                        &total_baskets,
                        &batch_total_former,
                        &total_formers,
                    ],
                )
                .await
            };

            match dst_batch_result {
                Ok(r) => tracing::info!(
                    "✅ dst batch_data upserted: {} rows, batch={}",
                    r.total(),
                    batch_no
                ),
                Err(e) => tracing::error!("❌ dst batch_data upsert failed: {}", e),
            }

            // ── Step 3: batch_data_log on DESTINATION ─────────────────────
            let crte_check_sql = format!(
                r#"SELECT COUNT(*) as cnt FROM {dst_db}.[wh_former_former_batch_data_log]
               WHERE batch_no = @P1 AND batch_action_name = 'CRTE'"#
            );

            let crte_exists: bool = {
                let stream_result = if to_lk {
                    lk_conn.query(&crte_check_sql, &[&batch_no]).await
                } else {
                    conn.query(&crte_check_sql, &[&batch_no]).await
                };
                match stream_result {
                    Ok(stream) => {
                        let rows = stream.into_first_result().await.unwrap_or_default();
                        rows.first()
                            .and_then(|r| r.get::<i32, _>("cnt"))
                            .unwrap_or(0)
                            > 0
                    }
                    Err(e) => {
                        tracing::error!("❌ CRTE check failed: {}", e);
                        false
                    }
                }
            };

            let sub_action_key = format!("{}{}{}", transit_log_action, batch_no, total_baskets);

            if !crte_exists {
                let query_dst_crte = format!(
                    r#"
                    INSERT INTO {dst_db}.[wh_former_former_batch_data_log]
                    (batch_no, batch_action_name, batch_sub_action_key,
                    batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split,
                    batch_qty_in_wh, batch_qty_total,
                    batch_basket_qty_stockout, batch_basket_qty_stockin,
                    batch_basket_qty_merge, batch_basket_qty_split,
                    batch_basket_qty_in_wh, batch_basket_qty_total,
                    batch_used_day, batch_change_day, create_at, update_at, is_confirmed)
                    SELECT
                        @P1, 'CRTE', '',
                        0, 0, 0, 0, @P2, batch_total_former,
                        0, 0, 0, 0, @P3, batch_total_basket,
                        @P4, GETDATE(), GETDATE(), GETDATE(), 0
                    FROM {dst_db}.[wh_former_former_batch_data] WHERE batch_no = @P1
                    "#
                );
                let r = if to_lk {
                    lk_conn
                        .execute(
                            &query_dst_crte,
                            &[
                                &batch_no,
                                &total_formers,
                                &total_baskets,
                                &former_used_day_b,
                            ],
                        )
                        .await
                } else {
                    conn.execute(
                        &query_dst_crte,
                        &[
                            &batch_no,
                            &total_formers,
                            &total_baskets,
                            &former_used_day_b,
                        ],
                    )
                    .await
                };
                match r {
                    Ok(rows) => tracing::info!("✅ dst CRTE log inserted: {} rows", rows.total()),
                    Err(e) => tracing::error!("❌ dst CRTE log insert failed: {}", e),
                }
            }

            let query_dst_transit_log = format!(
                r#"
                INSERT INTO {dst_db}.[wh_former_former_batch_data_log]
                (batch_no, batch_action_name, batch_sub_action_key,
                batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split,
                batch_qty_in_wh, batch_qty_total,
                batch_basket_qty_stockout, batch_basket_qty_stockin,
                batch_basket_qty_merge, batch_basket_qty_split,
                batch_basket_qty_in_wh, batch_basket_qty_total,
                batch_used_day, batch_change_day, create_at, update_at, is_confirmed)
                SELECT
                    @P1, @P2, @P3,
                    0, 0, 0, 0, batch_total_former_in_wh, batch_total_former,
                    0, 0, 0, 0, batch_total_basket_in_wh, batch_total_basket,
                    @P4, GETDATE(), GETDATE(), GETDATE(), 0
                FROM {dst_db}.[wh_former_former_batch_data] WHERE batch_no = @P1
                "#
            );
            let r = if to_lk {
                lk_conn
                    .execute(
                        &query_dst_transit_log,
                        &[
                            &batch_no,
                            &transit_log_action,
                            &sub_action_key,
                            &former_used_day_b,
                        ],
                    )
                    .await
            } else {
                conn.execute(
                    &query_dst_transit_log,
                    &[
                        &batch_no,
                        &transit_log_action,
                        &sub_action_key,
                        &former_used_day_b,
                    ],
                )
                .await
            };
            match r {
                Ok(rows) => tracing::info!(
                    "✅ dst {} log inserted: {} rows",
                    transit_log_action,
                    rows.total()
                ),
                Err(e) => tracing::error!("❌ dst {} log insert failed: {}", transit_log_action, e),
            }

            // ── Step 4: batch_data_log on SOURCE for tracking ─────────────
            let query_src_transit_log = format!(
                r#"
                INSERT INTO {src_db}.[wh_former_former_batch_data_log]
                (batch_no, batch_action_name, batch_sub_action_key,
                batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split,
                batch_qty_in_wh, batch_qty_total,
                batch_basket_qty_stockout, batch_basket_qty_stockin,
                batch_basket_qty_merge, batch_basket_qty_split,
                batch_basket_qty_in_wh, batch_basket_qty_total,
                batch_used_day, batch_change_day, batch_stockout_to,
                create_at, update_at, is_confirmed)
                SELECT
                    @P1, @P2, @P3,
                    0, 0, 0, 0, batch_total_former_in_wh, batch_total_former,
                    0, 0, 0, 0, batch_total_basket_in_wh, batch_total_basket,
                    @P4, GETDATE(), @P5,
                    GETDATE(), GETDATE(), 0
                FROM {src_db}.[wh_former_former_batch_data] WHERE batch_no = @P1
                "#
            );
            let src_stockout_to = if to_lk { "LK" } else { "GD" };
            let r = conn
                .execute(
                    &query_src_transit_log,
                    &[
                        &batch_no,
                        &transit_log_action,
                        &sub_action_key,
                        &former_used_day_b,
                        &src_stockout_to,
                    ],
                )
                .await;
            match r {
                Ok(rows) => tracing::info!(
                    "✅ src {} tracking log inserted: {} rows",
                    transit_log_action,
                    rows.total()
                ),
                Err(e) => tracing::error!(
                    "❌ src {} tracking log insert failed: {}",
                    transit_log_action,
                    e
                ),
            }

            // ── Step 5: Per-basket sync ───────────────────────────────────
            for rack in &payload.racks {
                for item in &rack.items {
                    if !item.basket_no.starts_with("3001")
                        && !item.basket_no.starts_with("3002")
                        && !item.basket_no.starts_with("3003")
                    {
                        tracing::warn!("⚠️ Skipping invalid basket_no: {}", item.basket_no);
                        continue;
                    }

                    let query_get_basket = format!(
                        r#"
                        SELECT basket_vendor, basket_capacity, basket_length,
                            basket_receive_qty, basket_receive_date, basket_purchase_order,
                            former_size, former_used_day, is_print
                        FROM {db}.[wh_former_basket_master_data]
                        WHERE basket_no = @P1
                        "#
                    );
                    let basket_row = match conn.query(&query_get_basket, &[&item.basket_no]).await {
                        Ok(s) => s.into_first_result().await.unwrap_or_default(),
                        Err(e) => {
                            tracing::error!(
                                "❌ Failed to fetch basket {} from GD: {}",
                                item.basket_no,
                                e
                            );
                            continue;
                        }
                    };

                    let Some(row) = basket_row.first() else {
                        tracing::warn!(
                            "⚠️ basket_no={} not found in GD — skipping",
                            item.basket_no
                        );
                        continue;
                    };

                    let basket_vendor = row
                        .get::<&str, _>("basket_vendor")
                        .unwrap_or("")
                        .to_string();
                    let basket_capacity = row
                        .try_get::<i32, _>("basket_capacity")
                        .ok()
                        .flatten()
                        .unwrap_or(0);
                    let basket_length = row
                        .try_get::<&str, _>("basket_length")
                        .ok()
                        .flatten()
                        .unwrap_or("")
                        .to_string();
                    let basket_receive_qty = row
                        .try_get::<i32, _>("basket_receive_qty")
                        .ok()
                        .flatten()
                        .unwrap_or(0);
                    let basket_receive_date = row
                        .try_get::<chrono::NaiveDate, _>("basket_receive_date")
                        .ok()
                        .flatten();
                    let basket_purchase_order = row
                        .get::<&str, _>("basket_purchase_order")
                        .unwrap_or("")
                        .to_string();
                    let former_size_basket =
                        row.get::<&str, _>("former_size").unwrap_or("").to_string();
                    let former_used_day_basket = row
                        .try_get::<i32, _>("former_used_day")
                        .ok()
                        .flatten()
                        .unwrap_or(0);
                    let is_print = row
                        .try_get::<i32, _>("is_print")
                        .ok()
                        .flatten()
                        .unwrap_or(0);

                    let query_dst_basket = format!(
                        r#"
                        MERGE {dst_db}.[wh_former_basket_master_data] AS target
                        USING (SELECT @P1 AS basket_no) AS source
                        ON (target.basket_no = source.basket_no)
                        WHEN MATCHED THEN
                            UPDATE SET
                                basket_vendor         = @P2,
                                basket_capacity       = @P3,
                                basket_length         = @P4,
                                basket_receive_qty    = @P5,
                                basket_purchase_order = @P6,
                                former_size           = @P7,
                                former_used_day       = @P8,
                                is_active             = @P9,
                                is_print              = @P10,
                                basket_receive_date   = @P11
                        WHEN NOT MATCHED THEN
                            INSERT (basket_no, basket_vendor, basket_capacity, basket_length,
                                    basket_receive_qty, basket_purchase_order,
                                    former_size, former_used_day, is_active, is_print,
                                    create_by_id, create_at, basket_receive_date)
                            VALUES (@P1, @P2, @P3, @P4, @P5, @P6, @P7, @P8, @P9, @P10,
                                    33, GETDATE(), @P11);
                        "#
                    );
                    let r = if to_lk {
                        lk_conn
                            .execute(
                                &query_dst_basket,
                                &[
                                    &item.basket_no,
                                    &basket_vendor,
                                    &basket_capacity,
                                    &basket_length,
                                    &basket_receive_qty,
                                    &basket_purchase_order,
                                    &former_size_basket,
                                    &former_used_day_basket,
                                    &dst_active,
                                    &is_print,
                                    &basket_receive_date,
                                ],
                            )
                            .await
                    } else {
                        conn.execute(
                            &query_dst_basket,
                            &[
                                &item.basket_no,
                                &basket_vendor,
                                &basket_capacity,
                                &basket_length,
                                &basket_receive_qty,
                                &basket_purchase_order,
                                &former_size_basket,
                                &former_used_day_basket,
                                &dst_active,
                                &is_print,
                                &basket_receive_date,
                            ],
                        )
                        .await
                    };
                    match r {
                        Ok(rows) => tracing::info!(
                            "✅ dst basket_master_data upserted: {} rows, basket={}",
                            rows.total(),
                            item.basket_no
                        ),
                        Err(e) => tracing::error!(
                            "❌ dst basket_master_data upsert failed for {}: {}",
                            item.basket_no,
                            e
                        ),
                    }

                    let dst_bin = if to_lk {
                        "LK".to_string()
                    } else {
                        rack.bin.clone()
                    };
                    let query_dst_bin = format!(
                        r#"
                        MERGE {dst_db}.[wh_former_former_bin_data] AS target
                        USING (SELECT @P1 AS basket_no) AS source
                        ON (target.basket_no = source.basket_no)
                        WHEN MATCHED THEN
                            UPDATE SET batch_no = @P2, bin = @P3,
                                    basket_former_qty = @P4, to_bin_key = '', update_at = GETDATE()
                        WHEN NOT MATCHED THEN
                            INSERT (basket_no, batch_no, bin, basket_former_qty, to_bin_key, update_at)
                            VALUES (@P1, @P2, @P3, @P4, '', GETDATE());
                        "#
                    );
                    let r = if to_lk {
                        lk_conn
                            .execute(
                                &query_dst_bin,
                                &[
                                    &item.basket_no,
                                    &batch_no,
                                    &dst_bin,
                                    &item.basket_former_qty,
                                ],
                            )
                            .await
                    } else {
                        conn.execute(
                            &query_dst_bin,
                            &[
                                &item.basket_no,
                                &batch_no,
                                &dst_bin,
                                &item.basket_former_qty,
                            ],
                        )
                        .await
                    };
                    match r {
                        Ok(rows) => tracing::info!(
                            "✅ dst bin_data upserted: {} rows, basket={}",
                            rows.total(),
                            item.basket_no
                        ),
                        Err(e) => tracing::error!(
                            "❌ dst bin_data upsert failed for {}: {}",
                            item.basket_no,
                            e
                        ),
                    }

                    let query_src_lending = format!(
                        r#"
                    UPDATE {src_db}.[wh_former_basket_master_data]
                    SET is_active = @P1
                    WHERE basket_no = @P2
                    "#
                    );
                    let r = conn
                        .execute(&query_src_lending, &[&src_active, &item.basket_no])
                        .await;
                    match r {
                        Ok(rows) => tracing::info!(
                            "✅ src basket marked as lending (is_active={}): {} rows, basket={}",
                            src_active,
                            rows.total(),
                            item.basket_no
                        ),
                        Err(e) => tracing::error!(
                            "❌ src basket lending update failed for {}: {}",
                            item.basket_no,
                            e
                        ),
                    }
                }
            }

            tracing::info!("✅ Transit sync complete (action={})", payload.action);
        }
    }
    // ==================== END GENERAL TRANSIT SECTION ====================

    tracing::info!("✅ Stock Out saved successfully");
    (
        StatusCode::OK,
        Json(StockOutSaveResponse {
            success: true,
            message: "Stock Out saved successfully".to_string(),
            total_baskets: Some(total_baskets),
            total_formers: Some(total_formers),
            batch_no: Some(batch_no),
        }),
    )
}

// ==================== EMPTY STOCK SAVE ====================

#[derive(Debug, Deserialize)]
struct EmptyStockSaveRequest {
    selected_machine: String,
    action: String,
    racks: Vec<EmptyStockRack>,
}

#[derive(Debug, Deserialize)]
struct EmptyStockRack {
    #[allow(dead_code)]
    rack_no: i32,
    bin: String,
    items: Vec<EmptyStockItem>,
}

#[derive(Debug, Deserialize)]
struct EmptyStockItem {
    #[allow(dead_code)]
    tag_id: String,
    basket_no: String,
    basket_former_qty: i32,
}

#[derive(Debug, Serialize)]
struct EmptyStockSaveResponse {
    success: bool,
    message: String,
    total_baskets: Option<i32>,
    total_formers: Option<i32>,
}

async fn handle_empty_stock_save(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<EmptyStockSaveRequest>,
) -> impl IntoResponse {
    tracing::info!(
        "📦 Empty Stock Save request: action={}, bin={}",
        payload.action,
        payload
            .racks
            .first()
            .map(|r| r.bin.as_str())
            .unwrap_or("N/A")
    );

    // 1. Calculate totals
    let total_baskets: i32 = payload.racks.iter().map(|r| r.items.len() as i32).sum();
    let total_formers: i32 = payload
        .racks
        .iter()
        .flat_map(|r| r.items.iter())
        .map(|i| i.basket_former_qty)
        .sum();

    tracing::info!(
        "📊 Totals: {} baskets, {} formers",
        total_baskets,
        total_formers
    );

    // 2. Get connection
    let mut conn = match state.pool.get().await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("❌ DB connection error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(EmptyStockSaveResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                    total_baskets: None,
                    total_formers: None,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // 3. Determine target bin
    let target_bin: String = if payload.action.to_lowercase() == "in" {
        "X".to_string()
    } else {
        payload.selected_machine.clone()
    };

    // 4. Process each item
    for rack in &payload.racks {
        for item in &rack.items {
            tracing::info!("🔄 Processing basket_no={}", item.basket_no);

            // 4a. Fetch batch_no and former_size for this basket (needed for log)
            let (batch_no_for_log, former_size_for_log) = {
                let query_fetch = format!(
                    r#"
                    SELECT bd.batch_no, b.former_size
                    FROM {db}.[wh_former_former_bin_data] bd
                    LEFT JOIN {db}.[wh_former_former_batch_data] b ON b.batch_no = bd.batch_no
                    WHERE bd.basket_no = @P1
                    "#
                );
                match conn.query(query_fetch, &[&item.basket_no]).await {
                    Ok(stream) => {
                        let rows = stream.into_first_result().await.unwrap_or_default();
                        if let Some(row) = rows.first() {
                            let bn = row.get::<&str, _>("batch_no").unwrap_or("").to_string();
                            let fs = row.get::<&str, _>("former_size").unwrap_or("").to_string();
                            (bn, fs)
                        } else {
                            (String::new(), String::new())
                        }
                    }
                    Err(e) => {
                        tracing::warn!(
                            "⚠️ Could not fetch batch/former_size for basket {}: {}",
                            item.basket_no,
                            e
                        );
                        (String::new(), String::new())
                    }
                }
            };

            // 4b. Capture the current bin before updating (used as from_bin in log)
            let from_bin_for_log = {
                let query_current_bin = format!(
                    r#"
                    SELECT bin FROM {db}.[wh_former_former_bin_data]
                    WHERE basket_no = @P1
                    "#
                );
                match conn.query(query_current_bin, &[&item.basket_no]).await {
                    Ok(stream) => {
                        let rows = stream.into_first_result().await.unwrap_or_default();
                        rows.first()
                            .and_then(|r| r.get::<&str, _>("bin"))
                            .unwrap_or("")
                            .to_string()
                    }
                    Err(_) => String::new(),
                }
            };

            // 4c. Update bin_data
            let query_bin = format!(
                r#"
                UPDATE {db}.[wh_former_former_bin_data]
                SET bin = @P1,
                    basket_former_qty = 0,
                    update_at = GETDATE()
                WHERE basket_no = @P2
            "#
            );

            if let Err(e) = conn
                .execute(query_bin, &[&target_bin, &item.basket_no])
                .await
            {
                tracing::error!("❌ bin_data update failed: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(EmptyStockSaveResponse {
                        success: false,
                        message: "Failed updating bin data".to_string(),
                        total_baskets: None,
                        total_formers: None,
                    }),
                );
            }

            // 4d. Update basket_master_data
            let query_master = format!(
                r#"
                UPDATE {db}.[wh_former_basket_master_data]
                SET former_size = NULL
                WHERE basket_no = @P1
            "#
            );

            if let Err(e) = conn.execute(query_master, &[&item.basket_no]).await {
                tracing::error!("❌ basket_master_data update failed: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(EmptyStockSaveResponse {
                        success: false,
                        message: "Failed updating basket master data".to_string(),
                        total_baskets: None,
                        total_formers: None,
                    }),
                );
            }

            // 4e. Insert bin_data_log
            // action: 'EMPY' when emptying into storage (action=in → X),
            //         'EMOUT' when sending to machine (action=out → machine)
            let log_action = if payload.action.to_lowercase() == "in" {
                "EMPTY_IN"
            } else {
                "EMPTY_OUT"
            };
            let query_bin_log = format!(
                r#"
                INSERT INTO {db}.[wh_former_former_bin_data_log]
                (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, @P5, @P6, 'empty_stock', @P7, 28, GETDATE());
                "#
            );
            match conn
                .execute(
                    query_bin_log,
                    &[
                        &batch_no_for_log,       // P1: batch_no
                        &item.basket_no,         // P2: basket_no
                        &from_bin_for_log,       // P3: from_bin (previous bin)
                        &target_bin,             // P4: to_bin (new bin)
                        &item.basket_former_qty, // P5: basket_former_qty (qty before emptying)
                        &log_action,             // P6: action
                        &former_size_for_log,    // P7: former_size from batch_data
                    ],
                )
                .await
            {
                Ok(_) => tracing::info!(
                    "✅ bin_data_log inserted for basket={} ({}→{})",
                    item.basket_no,
                    from_bin_for_log,
                    target_bin
                ),
                Err(e) => tracing::error!("❌ bin_data_log insert failed: {}", e),
            }
        }
    }

    tracing::info!("✅ Empty Stock saved successfully");

    (
        StatusCode::OK,
        Json(EmptyStockSaveResponse {
            success: true,
            message: format!(
                "Empty Stock {} to {} saved successfully",
                payload.action, target_bin
            ),
            total_baskets: Some(total_baskets),
            total_formers: Some(total_formers),
        }),
    )
}

#[derive(Debug, Serialize)]
struct BinListResponse {
    success: bool,
    message: String,
    bins: Vec<String>,
}

async fn handle_get_bins(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    tracing::info!("📦 Get bin list request");

    // 1. Get connection
    let mut conn = match state.pool.get().await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("❌ DB connection error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(BinListResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                    bins: vec![],
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // 2. Query
    let query = format!(
        r#"
        SELECT DISTINCT bin
        FROM {db}.[wh_former_former_bin_data]
        WHERE bin NOT LIKE '%NBR%'
          AND bin <> 'X'
          AND bin IS NOT NULL
        ORDER BY bin
    "#
    );

    // 3. Execute and collect rows
    let rows = match conn.query(query, &[]).await {
        Ok(result) => match result.into_first_result().await {
            Ok(rows) => rows,
            Err(e) => {
                tracing::error!("❌ Failed to read rows: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(BinListResponse {
                        success: false,
                        message: "Failed to read bin rows".to_string(),
                        bins: vec![],
                    }),
                );
            }
        },
        Err(e) => {
            tracing::error!("❌ Query failed: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(BinListResponse {
                    success: false,
                    message: "Failed to fetch bins".to_string(),
                    bins: vec![],
                }),
            );
        }
    };

    // 4. Convert rows to Vec<String>
    let bins: Vec<String> = rows
        .into_iter()
        .filter_map(|row| row.get::<&str, _>("bin").map(|b| b.to_string()))
        .collect();

    tracing::info!("✅ Retrieved {} bins", bins.len());

    // 5. Return response
    (
        StatusCode::OK,
        Json(BinListResponse {
            success: true,
            message: "Bins retrieved successfully".to_string(),
            bins,
        }),
    )
}

// ==================== FORMER MOVING SAVE ====================

#[derive(Default)]
struct BatchMove {
    basket_qty: i32,
    former_qty: i32,
}

async fn handle_former_moving_save(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<EmptyStockSaveRequest>,
) -> impl IntoResponse {
    tracing::info!("🚚 Former Moving request received");

    // =========================
    // CALCULATE TOTAL
    // =========================

    let total_baskets: i32 = payload.racks.iter().map(|r| r.items.len() as i32).sum();

    let total_formers: i32 = payload
        .racks
        .iter()
        .flat_map(|r| r.items.iter())
        .map(|i| i.basket_former_qty)
        .sum();

    // =========================
    // GET DB CONNECTION
    // =========================

    let mut conn = match state.pool.get().await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("❌ DB connection error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(EmptyStockSaveResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                    total_baskets: None,
                    total_formers: None,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // ==========================================
    // COLLECT PHASE (GROUP BY old_batch,new_batch)
    // ==========================================

    let mut batch_moves: HashMap<(String, String), BatchMove> = HashMap::new();

    for rack in &payload.racks {
        let new_bin = &rack.bin;

        if rack.items.is_empty() {
            tracing::info!("⚠️ No items in rack {}, skipping", rack.rack_no);
            continue;
        }

        // Get old batch using first basket
        let first_basket = &rack.items[0].basket_no;

        tracing::info!(
            "🔍 Processing rack {}, first_basket={}, new_bin={}",
            rack.rack_no,
            first_basket,
            new_bin
        );

        let query_old = format!(
            r#"
            SELECT TOP 1 batch_no
            FROM {db}.[wh_former_former_bin_data]
            WHERE basket_no = @P1
        "#
        );

        let stream = match conn.query(query_old, &[first_basket]).await {
            Ok(s) => s,
            Err(e) => {
                tracing::error!("❌ Query old batch failed: {}", e);
                continue;
            }
        };

        let rows: Vec<_> = stream.into_first_result().await.unwrap_or_default();

        if rows.is_empty() {
            continue;
        }

        let old_batch: String = rows[0].get::<&str, _>("batch_no").unwrap_or("").to_string();

        // Get new batch from bin
        let query_new = format!(
            r#"
            SELECT TOP 1 batch_no
            FROM {db}.[wh_former_former_bin_data]
            WHERE bin = @P1
        "#
        );

        let stream = match conn.query(query_new, &[new_bin]).await {
            Ok(s) => s,
            Err(e) => {
                tracing::error!("❌ Query new batch failed: {}", e);
                continue;
            }
        };

        let rows: Vec<_> = stream.into_first_result().await.unwrap_or_default();

        let new_batch: String = if rows.is_empty() {
            "".to_string()
        } else {
            rows[0].get::<&str, _>("batch_no").unwrap_or("").to_string()
        };

        let basket_qty = rack.items.len() as i32;
        let former_qty: i32 = rack.items.iter().map(|i| i.basket_former_qty).sum();

        let key = (old_batch.clone(), new_batch.clone());

        let entry = batch_moves.entry(key).or_default();
        entry.basket_qty += basket_qty;
        entry.former_qty += former_qty;

        // Fetch former_size from batch_data for log
        let former_size_for_log = {
            let query_fs = format!(
                r#"
                SELECT former_size FROM {db}.[wh_former_former_batch_data]
                WHERE batch_no = @P1
                "#
            );
            match conn.query(query_fs, &[&old_batch]).await {
                Ok(stream) => {
                    let rows = stream.into_first_result().await.unwrap_or_default();
                    rows.first()
                        .and_then(|r| r.get::<&str, _>("former_size"))
                        .unwrap_or("")
                        .to_string()
                }
                Err(_) => String::new(),
            }
        };

        // =========================
        // UPDATE BIN & COLLECT LOG DATA
        // =========================

        for item in &rack.items {
            // Fetch the current (from) bin before updating
            let from_bin = {
                let query_current_bin = format!(
                    r#"
                    SELECT bin FROM {db}.[wh_former_former_bin_data]
                    WHERE basket_no = @P1
                    "#
                );
                match conn.query(query_current_bin, &[&item.basket_no]).await {
                    Ok(stream) => {
                        let rows = stream.into_first_result().await.unwrap_or_default();
                        rows.first()
                            .and_then(|r| r.get::<&str, _>("bin"))
                            .unwrap_or("")
                            .to_string()
                    }
                    Err(_) => String::new(),
                }
            };

            let query_update_bin = format!(
                r#"
                UPDATE {db}.[wh_former_former_bin_data]
                SET
                    bin = @P1,
                    update_at = GETDATE()
                WHERE basket_no = @P2
            "#
            );

            tracing::info!(
                "   Updating bin for basket_no={}, new_bin={}",
                item.basket_no,
                new_bin
            );

            let _ = conn
                .execute(query_update_bin, &[new_bin, &item.basket_no])
                .await;

            // Insert bin_data_log immediately after bin update
            let query_bin_log = format!(
                r#"
                INSERT INTO {db}.[wh_former_former_bin_data_log]
                (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, @P5, 'MOVE', 'moving', @P6, 28, GETDATE());
                "#
            );
            match conn
                .execute(
                    query_bin_log,
                    &[
                        &old_batch,              // P1: batch_no
                        &item.basket_no,         // P2: basket_no
                        &from_bin,               // P3: from_bin (captured before update)
                        new_bin,                 // P4: to_bin
                        &item.basket_former_qty, // P5: basket_former_qty
                        &former_size_for_log,    // P6: former_size from batch_data
                    ],
                )
                .await
            {
                Ok(_) => tracing::info!(
                    "✅ bin_data_log inserted for moving basket={} ({}→{})",
                    item.basket_no,
                    from_bin,
                    new_bin
                ),
                Err(e) => tracing::error!(
                    "❌ bin_data_log insert failed for basket={}: {}",
                    item.basket_no,
                    e
                ),
            }
        }
    }

    // ==========================================
    // APPLY PHASE (UPDATE BATCH + INSERT LOG)
    // ==========================================

    for ((old_batch, new_batch), data) in batch_moves {
        if old_batch == new_batch || new_batch.is_empty() {
            continue;
        }

        let basket_qty = data.basket_qty;
        let former_qty = data.former_qty;

        // ---------- UPDATE OLD BATCH ----------

        let query_old_batch = format!(
            r#"
            UPDATE {db}.[wh_former_former_batch_data]
            SET
                batch_total_basket = batch_total_basket - @P1,
                batch_total_former = batch_total_former - @P2,
                batch_total_basket_in_wh = batch_total_basket_in_wh - @P1,
                batch_total_former_in_wh = batch_total_former_in_wh - @P2,
                update_at = GETDATE()
            WHERE batch_no = @P3
        "#
        );

        let _ = conn
            .execute(query_old_batch, &[&basket_qty, &former_qty, &old_batch])
            .await;

        // ---------- UPDATE NEW BATCH ----------

        let query_new_batch = format!(
            r#"
            UPDATE {db}.[wh_former_former_batch_data]
            SET
                batch_total_basket = batch_total_basket + @P1,
                batch_total_former = batch_total_former + @P2,
                batch_total_basket_in_wh = batch_total_basket_in_wh + @P1,
                batch_total_former_in_wh = batch_total_former_in_wh + @P2,
                update_at = GETDATE()
            WHERE batch_no = @P3
        "#
        );

        let _ = conn
            .execute(query_new_batch, &[&basket_qty, &former_qty, &new_batch])
            .await;

        // ---------- INSERT OLD BATCH LOG ----------

        let query_old_batch_log = format!(
            r#"
            INSERT INTO {db}.[wh_former_former_batch_data_log]
            (
                batch_no,
                batch_action_name,
                batch_qty_split,
                batch_qty_total,
                batch_qty_in_wh,
                batch_used_day,
                batch_change_day,
                batch_qty_merge,
                batch_qty_stockout,
                batch_basket_qty_in_wh,
                batch_basket_qty_merge,
                batch_basket_qty_split,
                batch_basket_qty_stockout,
                batch_basket_qty_total,
                create_at,
                update_at,
                batch_basket_qty_stockin,
                batch_qty_stockin,
                is_confirmed
            )
            SELECT
                batch_no,
                'MOUT',
                0,
                batch_qty_total - @P1,
                batch_qty_in_wh - @P1,
                batch_used_day,
                GETDATE(),
                0,
                0,
                batch_basket_qty_in_wh - @P2,
                0,
                0,
                0,
                batch_basket_qty_total - @P2,
                GETDATE(),
                GETDATE(),
                0,
                0,
                0
            FROM {db}.[wh_former_former_batch_data]
            WHERE batch_no = @P3
        "#
        );

        let _ = conn
            .execute(query_old_batch_log, &[&former_qty, &basket_qty, &old_batch])
            .await;

        // ---------- INSERT NEW BATCH LOG ----------

        let query_new_batch_log = format!(
            r#"
            INSERT INTO {db}.[wh_former_former_batch_data_log]
            (
                batch_no,
                batch_action_name,
                batch_qty_split,
                batch_qty_total,
                batch_qty_in_wh,
                batch_used_day,
                batch_change_day,
                batch_qty_merge,
                batch_qty_stockout,
                batch_basket_qty_in_wh,
                batch_basket_qty_merge,
                batch_basket_qty_split,
                batch_basket_qty_stockout,
                batch_basket_qty_total,
                create_at,
                update_at,
                batch_basket_qty_stockin,
                batch_qty_stockin,
                is_confirmed
            )
            SELECT
                batch_no,
                'MOIN',
                0,
                batch_qty_total + @P1,
                batch_qty_in_wh + @P1,
                batch_used_day,
                GETDATE(),
                0,
                0,
                batch_basket_qty_in_wh + @P2,
                0,
                0,
                0,
                batch_basket_qty_total + @P2,
                GETDATE(),
                GETDATE(),
                0,
                0,
                0
            FROM {db}.[wh_former_former_batch_data]
            WHERE batch_no = @P3
        "#
        );

        let _ = conn
            .execute(query_new_batch_log, &[&former_qty, &basket_qty, &new_batch])
            .await;
    }

    tracing::info!(
        "✅ Former Moving completed: {} baskets / {} formers",
        total_baskets,
        total_formers
    );

    (
        StatusCode::OK,
        Json(EmptyStockSaveResponse {
            success: true,
            message: "Former Moving saved successfully".to_string(),
            total_baskets: Some(total_baskets),
            total_formers: Some(total_formers),
        }),
    )
}

// ==================== FORMER CLEANING SAVE ====================
#[derive(Debug, Deserialize)]
struct FormerCleaningSaveRequest {
    stockout_form: String,
    action: String,
    source: String,
    racks: Vec<FormerCleaningRack>,
}

#[derive(Debug, Deserialize)]
struct FormerCleaningRack {
    #[allow(dead_code)]
    rack_no: i32,
    bin: String,
    items: Vec<FormerCleaningItem>,
}

#[derive(Debug, Deserialize)]
struct FormerCleaningItem {
    #[allow(dead_code)]
    tag_id: String,
    basket_no: String,
    basket_former_qty: i32,
}

#[derive(Debug, Serialize)]
struct FormerCleaningSaveResponse {
    success: bool,
    message: String,
    total_baskets: Option<i32>,
    total_formers: Option<i32>,
}

// Batch data struct for storing batch information
#[derive(Debug)]
struct BatchData {
    former_size: String,
    former_used_day: Option<i32>,
}

async fn handle_former_cleaning_save(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<FormerCleaningSaveRequest>,
) -> impl IntoResponse {
    tracing::info!(
        "🧼 Former cleaning request received with action: {}, source: {}, bin: {}",
        payload.action,
        payload.source,
        payload
            .racks
            .first()
            .map(|r| r.bin.as_str())
            .unwrap_or("N/A")
    );

    // Validate action and source combinations
    let valid_combinations = [
        ("warehouse", "none"),    // action: warehouse, source: none
        ("vendor", "warehouse"),  // action: vendor, source: warehouse
        ("vendor", "production"), // action: vendor, source: production
        ("production", "none"),   // action: production, source: none
    ];

    let is_valid = valid_combinations
        .iter()
        .any(|&(a, s)| a == payload.action && s == payload.source);

    if !is_valid {
        return (
            StatusCode::BAD_REQUEST,
            Json(FormerCleaningSaveResponse {
                success: false,
                message: format!(
                    "Invalid action/source combination: {}/{}. Valid combinations are: warehouse/warehouse, vendor/warehouse, vendor/production, production/production",
                    payload.action, payload.source
                ),
                total_baskets: None,
                total_formers: None,
            }),
        );
    }

    let total_baskets: i32 = payload.racks.iter().map(|r| r.items.len() as i32).sum();

    let total_formers: i32 = payload
        .racks
        .iter()
        .flat_map(|r| r.items.iter())
        .map(|i| i.basket_former_qty)
        .sum();

    let mut conn = match state.pool.get().await {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("❌ DB connection error: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(FormerCleaningSaveResponse {
                    success: false,
                    message: format!("Database connection error: {}", e),
                    total_baskets: None,
                    total_formers: None,
                }),
            );
        }
    };

    let db = &state.db_prefix;

    // =====================================
    // COLLECT PHASE (GROUP BY OLD BATCH)
    // =====================================

    let mut batch_map: HashMap<String, BatchMove> = HashMap::new();
    let mut batch_baskets: HashMap<String, Vec<String>> = HashMap::new();
    let mut batch_details: HashMap<String, BatchData> = HashMap::new();
    // Per-item log data keyed by old_batch: Vec<(basket_no, from_bin, qty)>
    let mut batch_item_details: HashMap<String, Vec<(String, String, i32)>> = HashMap::new();

    for rack in &payload.racks {
        if rack.items.is_empty() {
            continue;
        }

        let first_basket = &rack.items[0].basket_no;

        let query_old_batch = format!(
            r#"
            SELECT TOP 1
                b.batch_no,
                b.former_size,

                CASE 
                    WHEN sf.stockout_date IS NOT NULL
                    THEN b.former_used_day + DATEDIFF(DAY, sf.stockout_date, GETDATE())
                    ELSE b.former_used_day
                END AS former_used_day

            FROM {}.[wh_former_former_bin_data] bin

            INNER JOIN {}.[wh_former_former_batch_data] b 
                ON bin.batch_no = b.batch_no

            LEFT JOIN {}.[wh_former_former_stockout_form] sf
                ON sf.stockout_form = @P2

            WHERE bin.basket_no = @P1
            "#,
            db, db, db
        );

        let stream = match conn
            .query(query_old_batch, &[first_basket, &payload.stockout_form])
            .await
        {
            Ok(s) => s,
            Err(e) => {
                tracing::error!("❌ Query old batch failed for {}: {}", first_basket, e);
                continue;
            }
        };

        let rows = match stream.into_first_result().await {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("❌ Failed to get rows: {}", e);
                continue;
            }
        };

        if rows.is_empty() {
            tracing::warn!("⚠️ No batch found for basket: {}", first_basket);
            continue;
        }

        let row = &rows[0];
        let old_batch: String = match row.get::<&str, _>(0) {
            Some(v) => v.to_string(),
            None => {
                tracing::warn!("⚠️ Batch number is null for basket: {}", first_basket);
                continue;
            }
        };

        // Store batch details if not already stored
        if !batch_details.contains_key(&old_batch) {
            let former_size: String = row.get::<&str, _>(1).unwrap_or_else(|| "").to_string();
            let former_used_day: Option<i32> = row.get(2);

            batch_details.insert(
                old_batch.clone(),
                BatchData {
                    former_size,
                    former_used_day,
                },
            );
        }

        let basket_qty = rack.items.len() as i32;
        let former_qty: i32 = rack.items.iter().map(|i| i.basket_former_qty).sum();

        let entry = batch_map.entry(old_batch.clone()).or_default();
        entry.basket_qty += basket_qty;
        entry.former_qty += former_qty;

        let basket_vec = batch_baskets.entry(old_batch.clone()).or_default();
        // Per-item details needed for bin_data_log: (basket_no, from_bin, qty)
        // Stored alongside batch_baskets so we can emit the log in the apply phase
        // once target_batch (possibly a new sub-batch) is known.
        let item_details_vec = batch_item_details
            .entry(old_batch.clone())
            .or_insert_with(Vec::new);
        for item in &rack.items {
            basket_vec.push(item.basket_no.clone());

            // Fetch current from_bin for each item before the bulk bin update runs
            let from_bin = {
                let query_current_bin = format!(
                    r#"
                    SELECT bin FROM {db}.[wh_former_former_bin_data]
                    WHERE basket_no = @P1
                    "#
                );
                match conn.query(query_current_bin, &[&item.basket_no]).await {
                    Ok(stream) => {
                        let rows = stream.into_first_result().await.unwrap_or_default();
                        rows.first()
                            .and_then(|r| r.get::<&str, _>("bin"))
                            .unwrap_or("")
                            .to_string()
                    }
                    Err(_) => String::new(),
                }
            };

            item_details_vec.push((item.basket_no.clone(), from_bin, item.basket_former_qty));
        }
    }

    if batch_map.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(FormerCleaningSaveResponse {
                success: false,
                message: "No valid batches found for cleaning".to_string(),
                total_baskets: Some(total_baskets),
                total_formers: Some(total_formers),
            }),
        );
    }

    // =====================================
    // APPLY PHASE (PROCESS EACH BATCH ONCE)
    // =====================================

    let is_insert_flow = (payload.action == "warehouse")
        || (payload.action == "vendor" && payload.source == "warehouse");

    let is_update_flow = (payload.action == "production")
        || (payload.action == "vendor" && payload.source == "production");

    let stockout_action = match (payload.action.as_str(), payload.source.as_str()) {
        ("warehouse", "none") => "to_cleaning",
        ("vendor", "warehouse") => "to_vendor",
        ("vendor", "production") => "production_vendor",
        ("production", "none") => "production_cleaning",
        _ => "unknown",
    };

    // Log action code — computed once, reused per-basket inside the apply loop
    let log_action = match (payload.action.as_str(), payload.source.as_str()) {
        ("warehouse", "none") => "CLIN",
        ("vendor", "warehouse") => "VCLN",
        ("vendor", "production") => "VCLN",
        ("production", "none") => "PCLN",
        _ => "CLIN",
    };

    for (old_batch, data) in &batch_map {
        let baskets = match batch_baskets.get(old_batch) {
            Some(v) => v,
            None => continue,
        };

        let batch_detail = match batch_details.get(old_batch) {
            Some(d) => d,
            None => continue,
        };

        let basket_qty = data.basket_qty;
        let former_qty = data.former_qty;

        let basket_values = baskets
            .iter()
            .map(|b| format!("('{}')", b))
            .collect::<Vec<String>>()
            .join(",");

        let query_check_full_batch = format!(
            r#"
            SELECT
                CASE 
                    WHEN COUNT(b.basket_no) = COUNT(req.basket_no)
                    THEN 1
                    ELSE 0
                END AS is_full_batch
            FROM {}.[wh_former_former_bin_data] b
            LEFT JOIN (
                VALUES {}
            ) AS req(basket_no)
            ON b.basket_no = req.basket_no
            WHERE b.batch_no = @P1
            "#,
            db, basket_values
        );

        let stream = match conn
            .query(query_check_full_batch, &[&old_batch.as_str()])
            .await
        {
            Ok(s) => s,
            Err(e) => {
                tracing::error!("❌ Failed to check full batch {}: {}", old_batch, e);
                continue;
            }
        };

        let rows = match stream.into_first_result().await {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("❌ Failed to get full batch result: {}", e);
                continue;
            }
        };

        let is_full_batch: i32 = if rows.is_empty() {
            0
        } else {
            rows[0].get::<i32, _>(0).unwrap_or(0)
        };

        // =====================================
        // 1. UPDATE ORIGINAL BATCH DATA
        // =====================================
        let query_update_batch = if is_update_flow {
            format!(
                r#"
                UPDATE {}.[wh_former_former_batch_data]
                SET
                    batch_total_basket =
                        CASE 
                            WHEN @P4 = 1 THEN batch_total_basket
                            ELSE batch_total_basket - @P2
                        END,

                    batch_total_former =
                        CASE
                            WHEN @P4 = 1 THEN batch_total_former
                            ELSE batch_total_former - @P3
                        END,

                    update_at = GETDATE()

                WHERE batch_no = @P1
                "#,
                db
            )
        } else {
            format!(
                r#"
                UPDATE {}.[wh_former_former_batch_data]
                SET
                    batch_total_basket =
                        CASE 
                            WHEN @P4 = 1 THEN batch_total_basket
                            ELSE batch_total_basket - @P2
                        END,

                    batch_total_former =
                        CASE
                            WHEN @P4 = 1 THEN batch_total_former
                            ELSE batch_total_former - @P3
                        END,

                    batch_total_basket_in_wh = batch_total_basket_in_wh - @P2,
                    batch_total_former_in_wh = batch_total_former_in_wh - @P3,

                    update_at = GETDATE()

                WHERE batch_no = @P1
                "#,
                db
            )
        };

        match conn
            .execute(
                query_update_batch,
                &[old_batch, &basket_qty, &former_qty, &is_full_batch],
            )
            .await
        {
            Ok(_) => {
                tracing::info!(
                    "✅ Updated batch {} (full_batch={}): baskets {}, formers {}",
                    old_batch,
                    is_full_batch,
                    basket_qty,
                    former_qty
                );
            }
            Err(e) => {
                tracing::error!("❌ Failed to update batch {}: {}", old_batch, e);
                continue;
            }
        }

        let bin_target = match (payload.action.as_str(), payload.source.as_str()) {
            ("warehouse", "none") => "CLEAN",
            ("vendor", "warehouse") => "VC",
            ("vendor", "production") => "VC",
            ("production", "none") => "CLEAN",
            _ => "CLEAN",
        };

        // =====================================
        // 2. HANDLE BASED ON ACTION/SOURCE COMBINATION
        // =====================================
        if is_insert_flow {
            let stockout_to = if payload.action == "warehouse" {
                "CLEAN"
            } else {
                "VC"
            };

            let query_insert_stockout_form = format!(
                r#"
                INSERT INTO {}.[wh_former_former_stockout_form]
                (
                    stockout_form,
                    stockout_date,
                    stockout_action,
                    stockout_to,
                    stockout_from,
                    batch_no,
                    former_size,
                    stockout_total_basket,
                    stockout_total_former,
                    stockout_return_basket,
                    stockout_return_former,
                    machine_workorder,
                    most_batch_former_qty,
                    most_batch_used_day,
                    is_closed,
                    stockin_date,
                    is_confirmed
                )
                VALUES
                (
                    @P1,
                    GETDATE(),
                    @P2,
                    @P3,
                    '',
                    @P4,
                    @P5,
                    @P6,
                    @P7,
                    0,
                    0,
                    NULL,
                    @P7,
                    @P8,
                    0,
                    NULL,
                    0
                )
                "#,
                db
            );

            match conn
                .execute(
                    query_insert_stockout_form,
                    &[
                        &payload.stockout_form,
                        &stockout_action,
                        &stockout_to,
                        old_batch,
                        &batch_detail.former_size,
                        &basket_qty,
                        &former_qty,
                        &batch_detail.former_used_day,
                    ],
                )
                .await
            {
                Ok(_) => {
                    tracing::info!(
                        "✅ Inserted stockout form for batch {} (source: {})",
                        old_batch,
                        payload.source
                    );
                }
                Err(e) => {
                    tracing::error!(
                        "❌ Failed to insert stockout form for batch {}: {}",
                        old_batch,
                        e
                    );
                }
            }
        } else if is_update_flow {
            let query_update_stockout_form = format!(
                r#"
                UPDATE {}.[wh_former_former_stockout_form]
                SET
                    stockout_total_basket = stockout_total_basket - @P2,
                    stockout_total_former = stockout_total_former - @P3
                WHERE stockout_form = @P1
                "#,
                db
            );

            match conn
                .execute(
                    query_update_stockout_form,
                    &[&payload.stockout_form, &basket_qty, &former_qty],
                )
                .await
            {
                Ok(_) => {
                    tracing::info!(
                        "✅ Updated stockout form {} for batch {} (source: {})",
                        payload.stockout_form,
                        old_batch,
                        payload.source
                    );
                }
                Err(e) => {
                    tracing::error!(
                        "❌ Failed to update stockout form {}: {}",
                        payload.stockout_form,
                        e
                    );
                }
            }
        }

        // =====================================
        // 3. DETERMINE TARGET BATCH
        // =====================================

        let mut target_batch = old_batch.clone();

        if is_full_batch == 0 {
            let query_create_sub_batch = format!(
                r#"
                DECLARE @new_batch VARCHAR(25)

                SET @new_batch = 
                    @P1 
                    + 'SUB' 
                    + FORMAT(GETDATE(), 'ddMM') 
                    + RIGHT(CONVERT(varchar(36), NEWID()), 2)

                INSERT INTO {}.[wh_former_former_batch_data]
                (
                    batch_no,
                    former_size,
                    former_used_day,
                    former_aql,
                    is_active,
                    batch_total_basket,
                    batch_total_former,
                    batch_total_basket_in_wh,
                    batch_total_former_in_wh,
                    batch_last_stockout,
                    batch_data_date,
                    create_at,
                    update_at,
                    create_by_id,
                    update_by_id
                )
                SELECT
                    @new_batch,
                    former_size,
                    @P4,
                    former_aql,
                    is_active,
                    @P2,
                    @P3,
                    @P2,
                    @P3,
                    NULL,
                    GETDATE(),
                    GETDATE(),
                    GETDATE(),
                    28,
                    28
                FROM {}.[wh_former_former_batch_data]
                WHERE batch_no = @P1

                SELECT @new_batch AS new_batch
                "#,
                db, db
            );

            let stream = match conn
                .query(
                    query_create_sub_batch,
                    &[
                        old_batch,
                        &basket_qty,
                        &former_qty,
                        &batch_detail.former_used_day,
                    ],
                )
                .await
            {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!("❌ Create sub batch failed for {}: {}", old_batch, e);
                    continue;
                }
            };

            let rows = match stream.into_first_result().await {
                Ok(r) => r,
                Err(e) => {
                    tracing::error!("❌ Failed to get sub batch result: {}", e);
                    continue;
                }
            };

            if rows.is_empty() {
                tracing::error!("❌ No sub batch created for batch: {}", old_batch);
                continue;
            }

            target_batch = match rows[0].get::<&str, _>(0) {
                Some(val) => val.to_string(),
                None => {
                    tracing::error!("❌ Sub batch number is null");
                    continue;
                }
            };

            tracing::info!(
                "🆕 Created sub batch {} from {} (source: {})",
                target_batch,
                old_batch,
                payload.source
            );
        }

        // =====================================
        // UPDATE BIN FOR ALL BASKETS
        // =====================================

        let query_update_bin = format!(
            r#"
            UPDATE bin
            SET
                bin.bin = @P1,
                bin.batch_no = @P2,
                bin.update_at = GETDATE()
            FROM {}.[wh_former_former_bin_data] bin
            JOIN (
                VALUES {}
            ) AS baskets(basket_no)
            ON bin.basket_no = baskets.basket_no
            "#,
            db, basket_values
        );

        match conn
            .execute(query_update_bin, &[&bin_target, &target_batch])
            .await
        {
            Ok(_) => {
                tracing::info!(
                    "✅ Updated {} baskets → bin {} batch {} (source: {})",
                    baskets.len(),
                    bin_target,
                    target_batch,
                    payload.source
                );
            }
            Err(e) => {
                tracing::error!("❌ Failed to update bins: {}", e);
            }
        }

        // =====================================
        // 4. INSERT BATCH LOG
        // =====================================
        let query_batch_log = format!(
            r#"
            INSERT INTO {}.[wh_former_former_batch_data_log]
            (
                batch_no,
                batch_action_name,
                batch_qty_split,
                batch_qty_total,
                batch_qty_in_wh,
                batch_qty_merge,
                batch_qty_stockout,
                batch_basket_qty_in_wh,
                batch_basket_qty_merge,
                batch_basket_qty_split,
                batch_basket_qty_stockout,
                batch_basket_qty_total,
                batch_basket_qty_stockin,
                batch_qty_stockin,
                batch_change_day,
                create_at,
                update_at,
                is_confirmed
            )
            VALUES
            (
                @P1,
                'CLEANING',
                0,
                @P2,
                @P2,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                GETDATE(),
                GETDATE(),
                GETDATE(),
                0
            )
            "#,
            db
        );

        let _ = conn
            .execute(query_batch_log, &[&target_batch, &former_qty])
            .await;

        // =====================================
        // 5. INSERT bin_data_log PER BASKET
        // =====================================
        let former_size_log = batch_details
            .get(old_batch)
            .map(|d| d.former_size.as_str())
            .unwrap_or("");

        if let Some(item_details) = batch_item_details.get(old_batch) {
            for (basket_no, from_bin, qty) in item_details {
                let query_bin_log = format!(
                    r#"
                    INSERT INTO {db}.[wh_former_former_bin_data_log]
                    (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                    VALUES (@P1, @P2, @P3, @P4, @P5, @P6, 'cleaning', @P7, 28, GETDATE());
                    "#
                );
                match conn
                    .execute(
                        query_bin_log,
                        &[
                            &target_batch,    // P1: correct batch_no (sub-batch if split)
                            basket_no,        // P2: basket_no
                            from_bin,         // P3: from_bin captured before bulk update
                            &bin_target,      // P4: to_bin (same value used in bin update above)
                            qty,              // P5: basket_former_qty
                            &log_action,      // P6: action code
                            &former_size_log, // P7: former_size from batch_data
                        ],
                    )
                    .await
                {
                    Ok(_) => tracing::info!(
                        "✅ bin_data_log inserted for cleaning basket={} ({}→{})",
                        basket_no,
                        from_bin,
                        bin_target
                    ),
                    Err(e) => tracing::error!(
                        "❌ bin_data_log insert failed for cleaning basket={}: {}",
                        basket_no,
                        e
                    ),
                }
            }
        }
    }

    tracing::info!(
        "✅ Former cleaning completed: {} baskets / {} formers (action: {}, source: {})",
        total_baskets,
        total_formers,
        payload.action,
        payload.source
    );

    (
        StatusCode::OK,
        Json(FormerCleaningSaveResponse {
            success: true,
            message: format!(
                "Former cleaning saved successfully for action '{}' with source '{}' ({} baskets / {} formers)",
                payload.action, payload.source, total_baskets, total_formers
            ),
            total_baskets: Some(total_baskets),
            total_formers: Some(total_formers),
        }),
    )
}
