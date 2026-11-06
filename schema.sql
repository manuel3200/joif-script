-- Database Schema for MiVPN Cloud (Edge Node Manager / Central DB)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum for user statuses
CREATE TYPE user_status AS ENUM ('active', 'suspended', 'expired');

-- Enum for server statuses
CREATE TYPE server_status AS ENUM ('online', 'offline');

-- Servers/Nodes Table
CREATE TABLE IF NOT EXISTS servers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    ip_address VARCHAR(45) NOT NULL UNIQUE,
    api_key VARCHAR(255) NOT NULL, -- Secret key for Node-Manager auth
    status server_status DEFAULT 'online',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL, -- Encrypted for UI, sent in plain to Node-Manager for Linux auth
    hwid VARCHAR(255), -- Hardware ID for device locking
    expiration_date TIMESTAMP WITH TIME ZONE NOT NULL,
    max_connections INTEGER DEFAULT 1,
    status user_status DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Access Mapping (Which user can access which server)
CREATE TABLE IF NOT EXISTS user_server_access (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    server_id UUID REFERENCES servers(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, server_id)
);

-- Connections Log (For monitoring and banning)
CREATE TABLE IF NOT EXISTS connection_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    server_id UUID REFERENCES servers(id) ON DELETE CASCADE,
    hwid VARCHAR(255) NOT NULL,
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    disconnected_at TIMESTAMP WITH TIME ZONE
);
