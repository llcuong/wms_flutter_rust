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
struct AppState {
    pool: Pool<ConnectionManager>,
}

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load environment variables
    dotenvy::dotenv().ok();

    // Create database connection pool
    let pool = create_db_pool()
        .await
        .expect("Failed to create database pool");

    tracing::info!("✅ Database connection pool created successfully!");

    // Shared state
    let state = Arc::new(AppState { pool });

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
        .route("/wh_former/machines", get(handle_get_machines))
        .route("/wh_former/stockout_forms", get(handle_get_stockout_forms))
        .route("/wh_former/save_batch", post(handle_save_batch))
        .route("/wh_former/stockin/save", post(handle_stockin_save))
        .route("/wh_former/stockout/save", post(handle_stockout_save))
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

    // Build parameterized query with IN clause
    let placeholders: Vec<String> = (1..=count).map(|i| format!("@P{}", i)).collect();
    let in_clause = placeholders.join(", ");

    // Standard query for scanning baskets
    let query = format!(
        r#"
        SELECT DISTINCT
            bmd.basket_no,
            bmd.basket_vendor,
            bmd.basket_purchase_order,
            bmd.is_active
        FROM [VNWMS].[dbo].[wh_former_basket_master_data] bmd
        WHERE bmd.basket_no IN ({})
        AND EXISTS (
            SELECT 1 
            FROM [VNWMS].[dbo].[wh_former_former_bin_data] fbd 
            WHERE fbd.basket_no = bmd.basket_no 
            AND fbd.bin LIKE '%NBR%'
        )
        "#,
        in_clause
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
                        basket_purchase_order: row
                            .get::<&str, _>("basket_purchase_order")
                            .map(|s| s.to_string()),
                        status: Some(status_str.to_string()),
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

// stockout batch baskets
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

    // Build parameterized query with IN clause
    let placeholders: Vec<String> = (1..=count).map(|i| format!("@P{}", i)).collect();
    let in_clause = placeholders.join(", ");

    // Standard query for scanning baskets
    let query = format!(
        r#"
        SELECT DISTINCT
            bmd.basket_no,
            bmd.basket_vendor,
            bmd.basket_purchase_order,
            bmd.is_active
        FROM [VNWMS].[dbo].[wh_former_basket_master_data] bmd
        WHERE bmd.basket_no IN ({})
        AND EXISTS (
            SELECT 1 
            FROM [VNWMS].[dbo].[wh_former_former_bin_data] fbd 
            WHERE fbd.basket_no = bmd.basket_no 
            AND fbd.bin NOT LIKE '%NBR%'
        )
        "#,
        in_clause
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
                        basket_purchase_order: row
                            .get::<&str, _>("basket_purchase_order")
                            .map(|s| s.to_string()),
                        status: Some(status_str.to_string()),
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

/// Create SQL Server connection pool
async fn create_db_pool() -> Result<Pool<ConnectionManager>, Box<dyn std::error::Error>> {
    // Get database configuration from environment
    let host = std::env::var("DATABASE_HOST").unwrap_or_else(|_| "localhost".to_string());
    let port: u16 = std::env::var("DATABASE_PORT")
        .unwrap_or_else(|_| "1433".to_string())
        .parse()?;
    let database = std::env::var("DATABASE_NAME").unwrap_or_else(|_| "WMS".to_string());
    let user = std::env::var("DATABASE_USER").unwrap_or_else(|_| "sa".to_string());
    let password = std::env::var("DATABASE_PASSWORD").expect("DATABASE_PASSWORD must be set");

    tracing::info!(
        "📦 Connecting to SQL Server: {}:{}/{}",
        host,
        port,
        database
    );

    // Configure SQL Server connection
    let mut config = Config::new();
    config.host(&host);
    config.port(port);
    config.database(&database);
    config.authentication(AuthMethod::sql_server(&user, &password));
    config.encryption(EncryptionLevel::Off); // Change to Required for production with SSL
    config.trust_cert();

    // Create connection manager
    let manager = ConnectionManager::new(config);

    // Build the pool with configuration
    let pool = Pool::builder()
        .max_size(10)
        .min_idle(Some(2))
        .build(manager)
        .await?;

    // Test connection
    let conn = pool.get().await?;
    tracing::info!("✅ Test connection successful!");
    drop(conn);

    Ok(pool)
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
}

#[derive(Debug, Serialize, Clone)]
struct BasketData {
    tag_id: String,
    basket_vendor: Option<String>,
    basket_purchase_order: Option<String>,
    status: Option<String>,
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

    tracing::info!("📥 Received batch of {} tags", count);

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

    // Build parameterized query with IN clause
    let placeholders: Vec<String> = (1..=count).map(|i| format!("@P{}", i)).collect();
    let in_clause = placeholders.join(", ");

    // Query matching the provided Django model: wh_former.models.Basket_master_data
    // Table name assumed based on standard Django naming or user input: wh_former_basket_master_data
    let query = format!(
        r#"
        SELECT 
            basket_no,
            basket_vendor,
            basket_purchase_order,
            is_active
        FROM [VNWMS].[dbo].[wh_former_basket_master_data]
        WHERE basket_no IN ({})
        "#,
        in_clause
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
                        basket_purchase_order: row
                            .get::<&str, _>("basket_purchase_order")
                            .map(|s| s.to_string()),
                        status: Some(status_str.to_string()),
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

    // Determine query based on group
    let (query, param) = match group {
        "length" => (
            r#"
            SELECT code, name 
            FROM [VNWMS].[dbo].[wh_former_parameter_data] 
            WHERE [group] = 'length' AND belong = 'former' AND is_active = 1
            ORDER BY id
            "#,
            None,
        ),
        "vendor" | "brand" => (
            // Map 'brand' request to 'vendor' query logic if needed, or stick to strict group name
            r#"
            SELECT code, name 
            FROM [VNWMS].[dbo].[wh_former_parameter_data] 
            WHERE [group] = 'vendor' AND belong = 'former' AND is_active = 1
            ORDER BY id
            "#,
            None,
        ),
        "itemno" | "itemNo" => (
            r#"
            SELECT code, name 
            FROM [VNWMS].[dbo].[wh_former_parameter_data] 
            WHERE [group] = 'itemno' AND is_active = 1
            ORDER BY id
            "#,
            None,
        ),
        _ => (
            // Default query for 'size' and others
            r#"
            SELECT code, name 
            FROM [VNWMS].[dbo].[wh_former_parameter_data] 
            WHERE [group] = @P1 
            ORDER BY id
            "#,
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

    // 1. Check if item_no exists and get current value
    // We update atomically by incrementing value and outputting the inserted/updated value
    // Using simple transaction-like logic or direct update with output

    // T-SQL to update and return the new value atomically
    let query = r#"
        UPDATE [VNWMS].[dbo].[wh_former_parameter_data]
        SET value = ISNULL(value, 0) + 1
        OUTPUT INSERTED.value
        WHERE name = @P1 AND is_active = 1
    "#;

    let mut query_builder = tiberius::Query::new(query);
    query_builder.bind(&item_no);

    let result = query_builder.query(&mut *conn).await;

    match result {
        Ok(stream) => {
            match stream.into_first_result().await {
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
                        // User requested fallback: if not found, assume 1
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
            }
        }
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
// #[derive(Debug, Serialize)]
// struct BinData {
//     bin_id: String,
//     bin_name: Option<String>,
//     area_id: Option<String>,
// }

// #[derive(Debug, Serialize)]
// struct BinResponse {
//     data: Vec<BinData>,
//     success: bool,
//     message: String,
// }

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

    // Get former areas (same logic as Django)
    let area_query = r#"
        SELECT area_id, area_name, pos_x, pos_y, area_w, area_l
        FROM [VNWMS].[dbo].[warehouse_area] a
        JOIN [VNWMS].[dbo].[warehouse_warehouse] w ON a.warehouse_id = w.wh_code
        WHERE w.wh_former_func = 1
        AND area_id LIKE '%FM%'
        AND w.wh_code NOT LIKE '%MACH%'
    "#;

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
        let bin_query = r#"
            SELECT
                b.bin_id,
                b.bin_name,
                COUNT(u.basket_no) as batch_count
            FROM [VNWMS].[dbo].[warehouse_bin] b
            LEFT JOIN (
                SELECT fbd.bin AS bin_id, fbd.basket_no
                FROM [VNWMS].[dbo].[wh_former_former_bin_data] fbd
        
                UNION
                SELECT frbt.from_bin AS bin_id, frbaskett.basket_no
                FROM [VNWMS].[dbo].[wh_former_former_rack_bin_temp] frbt
                JOIN [VNWMS].[dbo].[wh_former_former_rack_basket_temp] frbaskett
                  ON frbaskett.rack_temp_id = frbt.rack_temp_id
            ) AS u
            ON u.bin_id = b.bin_id
            WHERE b.area_id = @P1
            GROUP BY b.bin_id, b.bin_name
            ORDER BY b.bin_id
        "#;

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
// async fn handle_get_bins(State(state): State<Arc<AppState>>) -> impl IntoResponse {
//     tracing::info!("📥 Fetching bins");

//     let mut conn = match state.pool.get().await {
//         Ok(conn) => conn,
//         Err(e) => {
//             tracing::error!("❌ Failed to get database connection: {}", e);
//             return (
//                 StatusCode::SERVICE_UNAVAILABLE,
//                 Json(BinResponse {
//                     data: vec![],
//                     success: false,
//                     message: format!("Database connection error: {}", e),
//                 }),
//             );
//         }
//     };

//     let query = r#"
//         SELECT [bin_id]
//             ,[bin_name]
//             ,[area_id]
//         FROM [VNWMS].[dbo].[warehouse_bin]
//         WHERE [area_id] LIKE '%FM-%'
//         ORDER BY bin_id
//     "#;

//     let result = conn.simple_query(query).await;

//     match result {
//         Ok(stream) => {
//             let items = stream.into_first_result().await;
//             match items {
//                 Ok(rows) => {
//                     let mut data = Vec::new();
//                     for row in rows {
//                         let bin = BinData {
//                             bin_id: row.get::<&str, _>("bin_id").unwrap_or_default().to_string(),
//                             bin_name: row.get::<&str, _>("bin_name").map(|s| s.to_string()),
//                             area_id: row.get::<&str, _>("area_id").map(|s| s.to_string()),
//                         };
//                         data.push(bin);
//                     }
//                     tracing::info!("✅ Found {} bins", data.len());
//                     (
//                         StatusCode::OK,
//                         Json(BinResponse {
//                             data,
//                             success: true,
//                             message: "Success".to_string(),
//                         }),
//                     )
//                 }
//                 Err(e) => {
//                     tracing::error!("❌ Failed to fetch results: {}", e);
//                     (
//                         StatusCode::INTERNAL_SERVER_ERROR,
//                         Json(BinResponse {
//                             data: vec![],
//                             success: false,
//                             message: format!("Query execution error: {}", e),
//                         }),
//                     )
//                 }
//             }
//         }
//         Err(e) => {
//             tracing::error!("❌ Failed to query: {}", e);
//             (
//                 StatusCode::INTERNAL_SERVER_ERROR,
//                 Json(BinResponse {
//                     data: vec![],
//                     success: false,
//                     message: format!("Query error: {}", e),
//                 }),
//             )
//         }
//     }
// }

use chrono::NaiveDate;

// ... (existing imports)

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

    let query = r#"
        SELECT TOP (1000) [area_id]
            ,[area_name]
        FROM [VNWMS].[dbo].[warehouse_area]
        WHERE warehouse_id LIKE '%MACH%'
        ORDER BY area_name
    "#;

    // Fix borrowing issue by executing query and mapping result outside match
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

    let mut query = r#"
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
        FROM [VNWMS].[dbo].[wh_former_former_stockout_form]
        WHERE stockout_to = @P1 AND is_confirmed = 0
    "#
    .to_string();

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
                // Fix: Explicitly handle valid NaiveDate or string
                // Fix: Explicitly handle valid NaiveDate or string using safe try_get
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
    former_receive_form: String, // Added
    former_item_no: String,
    former_used_day: i32,
    former_aql: Option<f32>,
    batch_data_date: String,
}

#[derive(Debug, Deserialize)]
struct RackData {
    // rack_no: i32,
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
        MERGE [VNWMS].[dbo].[wh_former_former_batch_data] AS target
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
    let query_batch_log = r#"
        INSERT INTO [VNWMS].[dbo].[wh_former_former_batch_data_log]
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
    "#;

    let _ = conn
        .execute(
            query_batch_log,
            &[
                &payload.batch_no,
                &total_former,
                &(total_basket as i32),
                // &user_id, // Hardcoded to 1 for now as per previous request
            ],
        )
        .await;

    // 4. Loop items
    for rack in &payload.racks {
        for item in &rack.items {
            // a. Update Basket Master
            let query_basket = r#"
                UPDATE [VNWMS].[dbo].[wh_former_basket_master_data]
                SET is_active = 1, 
                    former_used_day = @P1, 
                    former_size = @P2
                WHERE basket_no = @P3;
            "#;
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
            let query_bin = r#"
                MERGE [VNWMS].[dbo].[wh_former_former_bin_data] AS target
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
            "#;
            let _ = conn
                .execute(
                    query_bin,
                    &[&item.tag_id, &item.bin, &item.quantity, &payload.batch_no],
                )
                .await;

            // c. Log Bin Data
            let query_bin_log = r#"
                INSERT INTO [VNWMS].[dbo].[wh_former_former_bin_data_log]
                (batch_no, basket_no, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, 'CRTE', 'stockin', @P5, 28, GETDATE());
            "#;
            let _ = conn
                .execute(
                    query_bin_log,
                    &[
                        &payload.batch_no,
                        &item.tag_id,
                        &item.bin,
                        &item.quantity,
                        &payload.master_info.former_size,
                        // &user_id, // Hardcoded 1
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

    // 1. Get stockout form info (batch_no, most_batch_used_day, stockout_date)
    let (batch_no, used_day): (String, i32) = {
        let query_get_form = r#"
            SELECT batch_no, most_batch_used_day, stockout_date
            FROM [VNWMS].[dbo].[wh_former_former_stockout_form]
            WHERE stockout_form = @P1
              AND former_size = @P2
              AND stockout_to = @P3
        "#;

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

        // Calculate used_day = most_batch_used_day + (today - stockout_date).days + 10
        let stockout_date = row
            .try_get::<chrono::NaiveDate, _>("stockout_date")
            .ok()
            .flatten();
        let days_diff = stockout_date
            .map(|d| (chrono::Local::now().date_naive() - d).num_days() as i32)
            .unwrap_or(0);
        let calculated_used_day = most_used_day + days_diff + 10;

        (batch, calculated_used_day)
    };

    tracing::info!("📋 Found batch_no={}, used_day={}", batch_no, used_day);

    // 2. Update stockout_form (return counts)
    let query_update_form = r#"
        UPDATE [VNWMS].[dbo].[wh_former_former_stockout_form]
        SET stockout_return_basket = stockout_return_basket + @P1,
            stockout_return_former = stockout_return_former + @P2,
            stockin_date = CASE WHEN stockin_date IS NULL THEN GETDATE() ELSE stockin_date END
        WHERE stockout_form = @P3
          AND former_size = @P4
          AND stockout_to = @P5
    "#;
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
            let query_basket = r#"
                UPDATE [VNWMS].[dbo].[wh_former_basket_master_data]
                SET is_active = 1, 
                    former_used_day = @P1, 
                    former_size = @P2
                WHERE basket_no = @P3;
            "#;
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

            // 3b. Upsert bin_data (basket_no and batch_no are string columns via db_column)
            let query_bin = r#"
                MERGE [VNWMS].[dbo].[wh_former_former_bin_data] AS target
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
            "#;
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
            let query_bin_log = r#"
                INSERT INTO [VNWMS].[dbo].[wh_former_former_bin_data_log]
                (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, @P5, 'STIN', 'stockin', @P6, 28, GETDATE());
            "#;
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
            let query_rfid = r#"
                UPDATE [VNWMS].[dbo].[wh_former_rfid_read_log]
                SET is_used = 1
                WHERE basket_no = @P1 AND is_used = 0;
            "#;
            match conn.execute(query_rfid, &[&item.basket_no]).await {
                Ok(result) => tracing::info!("✅ rfid_read_log updated: {} rows", result.total()),
                Err(e) => tracing::error!("❌ rfid_read_log update failed: {}", e),
            }
        }
    }

    // 4. Upsert batch_data_log
    let log_exists = {
        let query_check_log = r#"
            SELECT COUNT(*) as cnt FROM [VNWMS].[dbo].[wh_former_former_batch_data_log]
            WHERE batch_no = @P1 AND batch_action_name = 'STIN' AND batch_sub_action_key = @P2
        "#;
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
        let query_update_log = r#"
            UPDATE [VNWMS].[dbo].[wh_former_former_batch_data_log]
            SET batch_qty_in_wh = batch_qty_in_wh + @P1,
                batch_qty_stockin = batch_qty_stockin + @P1,
                batch_basket_qty_in_wh = batch_basket_qty_in_wh + @P2,
                batch_basket_qty_stockin = batch_basket_qty_stockin + @P2
            WHERE batch_no = @P3 AND batch_action_name = 'STIN' AND batch_sub_action_key = @P4
        "#;
        let _ = conn
            .execute(
                query_update_log,
                &[&total_formers, &total_baskets, &batch_no, &key],
            )
            .await;
    } else {
        // Insert new log with all required NOT NULL columns
        let query_insert_log = r#"
            INSERT INTO [VNWMS].[dbo].[wh_former_former_batch_data_log]
            (batch_no, batch_action_name, batch_sub_action_key, 
             batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split, batch_qty_in_wh, batch_qty_total,
             batch_basket_qty_stockout, batch_basket_qty_stockin, batch_basket_qty_merge, batch_basket_qty_split, batch_basket_qty_in_wh, batch_basket_qty_total,
             batch_used_day, batch_change_day, create_at, update_at, is_confirmed)
            SELECT 
                @P1, 'STIN', @P2,
                0, @P3, 0, 0, batch_total_former_in_wh + @P3, batch_total_former,
                0, @P4, 0, 0, batch_total_basket_in_wh + @P4, batch_total_basket,
                @P5, GETDATE(), GETDATE(), GETDATE(), 0
            FROM [VNWMS].[dbo].[wh_former_former_batch_data] WHERE batch_no = @P1
        "#;
        let _ = conn
            .execute(
                query_insert_log,
                &[&batch_no, &key, &total_formers, &total_baskets, &used_day],
            )
            .await;
    }

    // 5. Update batch_data
    let query_update_batch = r#"
        UPDATE [VNWMS].[dbo].[wh_former_former_batch_data]
        SET batch_total_basket_in_wh = batch_total_basket_in_wh + @P1,
            batch_total_former_in_wh = batch_total_former_in_wh + @P2,
            former_used_day = @P3,
            update_by_id = 28,
            update_at = GETDATE()
        WHERE batch_no = @P4
    "#;
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
        "📦 Stock Out Save request: form={}, machine={}",
        payload.stockout_form,
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

    // 1. Get stockout form info (batch_no, used_day) If not found -> derive batch from basket list
    let (batch_no, used_day, is_exist): (String, i32, bool) = {
        let query_get_form = r#"
        SELECT batch_no, most_batch_used_day
        FROM [VNWMS].[dbo].[wh_former_former_stockout_form]
        WHERE stockout_form = @P1
          AND former_size = @P2
          AND stockout_to = @P3
    "#;

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
                    FROM [VNWMS].[dbo].[wh_former_former_bin_data]
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

            // get used_day from batch table
            let base_used_day: i32 = {
                let query_batch = r#"
                SELECT former_used_day
                FROM [VNWMS].[dbo].[wh_former_former_batch_data]
                WHERE batch_no = @P1
            "#;

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

    //
    // Calculate totals
    //
    let total_baskets: i32 = payload.racks.iter().map(|r| r.items.len() as i32).sum();
    let total_formers: i32 = payload
        .racks
        .iter()
        .flat_map(|r| r.items.iter())
        .map(|i| i.basket_former_qty)
        .sum();

    let most_batch_former_qty = total_formers;

    //
    // 2. UPSERT stockout_form with return counts and used_day
    //
    if is_exist {
        // UPDATE
        let update_sql = r#"
        UPDATE [VNWMS].[dbo].[wh_former_former_stockout_form]
        SET stockout_date = GETDATE(),
            stockout_action = @P8,
            stockout_to = @P7,
            stockout_from = @P11,
            batch_no = @P9,
            former_size = @P10,
            stockout_total_basket = @P1,
            stockout_total_former = @P2,
            most_batch_former_qty = @P3,
            most_batch_used_day = @P4,
            update_at = GETDATE()
        WHERE stockout_form = @P5
    "#;

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
        // INSERT
        let insert_sql = r#"
        INSERT INTO [VNWMS].[dbo].[wh_former_former_stockout_form] (
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
            most_batch_former_qty,
            most_batch_used_day,
            is_closed,
            is_confirmed
        )
        VALUES (
            @P1, GETDATE(), @P9, @P2, @P10, @P3, @P4,
            @P5, @P6,
            0, 0,
            @P7, @P8,
            0, 0
        )
    "#;

        let _ = conn
            .execute(
                insert_sql,
                &[
                    &payload.stockout_form,
                    &payload.selected_machine,
                    &batch_no,
                    &payload.former_size,
                    &total_baskets,
                    &total_formers,
                    &most_batch_former_qty,
                    &used_day,
                    &payload.action,
                    &payload.stockout_from,
                ],
            )
            .await;
    }

    // 3. Process each rack and item
    let key = format!("KEY{}{}", payload.stockout_form, payload.former_size);

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
            let query_basket = r#"
                UPDATE [VNWMS].[dbo].[wh_former_basket_master_data]
                SET is_active = 1, 
                    former_used_day = @P1, 
                    former_size = @P2
                WHERE basket_no = @P3;
            "#;
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

            // 3b. Upsert bin_data (basket_no and batch_no are string columns via db_column)
            let query_bin = r#"
                MERGE [VNWMS].[dbo].[wh_former_former_bin_data] AS target
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
            "#;
            match conn
                .execute(
                    query_bin,
                    &[
                        &item.basket_no,
                        &payload.selected_machine, // bin = machine for stockout
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
            let query_bin_log = r#"
                INSERT INTO [VNWMS].[dbo].[wh_former_former_bin_data_log]
                (batch_no, basket_no, from_bin, to_bin, basket_former_qty, action, action_form, former_size, create_by_id, create_at)
                VALUES (@P1, @P2, @P3, @P4, @P5, 'STIN', 'stockin', @P6, 28, GETDATE());
            "#;
            match conn
                .execute(
                    query_bin_log,
                    &[
                        &batch_no,
                        &item.basket_no,
                        &rack.bin,                                  // from_bin = bin
                        &payload.selected_machine,                 // to_bin = machine for stockout
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
            let query_rfid = r#"
                UPDATE [VNWMS].[dbo].[wh_former_rfid_read_log]
                SET is_used = 1
                WHERE basket_no = @P1 AND is_used = 0;
            "#;
            match conn.execute(query_rfid, &[&item.basket_no]).await {
                Ok(result) => tracing::info!("✅ rfid_read_log updated: {} rows", result.total()),
                Err(e) => tracing::error!("❌ rfid_read_log update failed: {}", e),
            }
        }
    }

    // 4. Upsert batch_data_log
    let log_exists = {
        let query_check_log = r#"
            SELECT COUNT(*) as cnt FROM [VNWMS].[dbo].[wh_former_former_batch_data_log]
            WHERE batch_no = @P1 AND batch_action_name = 'STOU' AND batch_sub_action_key = @P2
        "#;
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
        let query_update_log = r#"
            UPDATE [VNWMS].[dbo].[wh_former_former_batch_data_log]
            SET batch_qty_in_wh = batch_qty_in_wh - @P1,
                batch_change_day = GETDATE(),
                batch_stockout_to = @P5,
                batch_qty_stockout = batch_qty_stockout + @P1,
                batch_basket_qty_in_wh = batch_basket_qty_in_wh - @P2,
                batch_basket_qty_stockout = batch_basket_qty_stockout + @P2
            WHERE batch_no = @P3 AND batch_action_name = 'STOU' AND batch_sub_action_key = @P4
        "#;
        let _ = conn
            .execute(
                query_update_log,
                &[&total_formers, &total_baskets, &batch_no, &key, &payload.selected_machine],
            )
            .await;
    } else {
        // Insert new log with all required NOT NULL columns
        let query_insert_log = r#"
            INSERT INTO [VNWMS].[dbo].[wh_former_former_batch_data_log]
            (batch_no, batch_action_name, batch_sub_action_key, 
             batch_qty_stockout, batch_qty_stockin, batch_qty_merge, batch_qty_split, batch_qty_in_wh, batch_qty_total,
             batch_basket_qty_stockout, batch_basket_qty_stockin, batch_basket_qty_merge, batch_basket_qty_split, batch_basket_qty_in_wh, batch_basket_qty_total,
             batch_used_day, batch_change_day, create_at, update_at, is_confirmed, batch_stockout_to)
            SELECT 
                @P1, 'STOU', @P2,
                @P3, 0, 0, 0, batch_total_former_in_wh - @P3, batch_total_former,
                @P4, 0, 0, 0, batch_total_basket_in_wh - @P4, batch_total_basket,
                @P5, GETDATE(), GETDATE(), GETDATE(), 0, @P6
            FROM [VNWMS].[dbo].[wh_former_former_batch_data] WHERE batch_no = @P1
        "#;
        let _ = conn
            .execute(
                query_insert_log,
                &[&batch_no, &key, &total_formers, &total_baskets, &used_day, &payload.selected_machine],
            )
            .await;
    }

    // 5. Update batch_data
    let query_update_batch = r#"
        UPDATE [VNWMS].[dbo].[wh_former_former_batch_data]
        SET batch_total_basket_in_wh = batch_total_basket_in_wh - @P1,
            batch_total_former_in_wh = batch_total_former_in_wh - @P2,
            former_used_day = @P3,
            update_by_id = 28,
            update_at = GETDATE()
        WHERE batch_no = @P4
    "#;
    let _ = conn
        .execute(
            query_update_batch,
            &[&total_baskets, &total_formers, &used_day, &batch_no],
        )
        .await;

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
