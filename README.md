# tourismapp
demo video and apk file here https://drive.google.com/drive/folders/1Ji-xiLdNH33YSP916Kn63xNgbUIBuYYs?usp=sharing
SUMARY
----------------------
Project Introduction 
----------------------
The demand for independent travel and backpacking is rapidly increasing. However, travelers frequently encounter significant challenges, primarily the lack of reliable internet connectivity in remote areas or foreign countries. Furthermore, sifting through massive amounts of online information to find locations that match personal preferences is incredibly time-consuming.
Currently available travel applications are often not optimized for solo travelers or small groups. They lack the necessary features for spontaneous exploration and fail to truly personalize the travel experience. A major pain point is the disconnect between independent travelers and local service providers. This gap makes it difficult for tourists to discover authentic local dining, entertainment, and hidden gems that align with their specific tastes.
Additionally, the fragmented nature of travel tools forces users to juggle multiple applications simultaneously—switching between apps for map navigation, discovering local eateries, storing travel documents, and itinerary planning.
To address these challenges, we have developed a comprehensive travel companion application. Our solution integrates all essential travel tools into a single platform. Most importantly, it bridges the gap between travelers and the local community, connecting users directly with local businesses and hidden spots. By combining robust offline capabilities with personalized, AI-driven recommendations, this application empowers backpackers to seamlessly discover, connect, and elevate their travel experience, no matter where their journey takes them.
___________________________________________________________________________________________________________________________________________________________________
SYSTEM ARCHITECTURE & TECHNICAL IMPLEMENTATION
Project Objectives
------------------------------------------------
The system was successfully architected as a comprehensive Client-Server ecosystem (Mobile App + Backend API) designed to deliver:
Multi-Source Discovery: Aggregate and display location data utilizing OpenStreetMap (OSM) and Foursquare APIs.
Offline Capabilities: Enable downloading and rendering of highly detailed maps for offline navigation.
Personalized Intelligence: Store user preferences, favorites, and search histories to generate customized location recommendations.
Supplier Portal: Provide a dedicated management interface for local business owners (Suppliers) to publish locations and run localized advertisements.
Travel Utilities: Offer built-in tools for itinerary planning and secure travel document storage.
Local Connection: Bridge the gap between tourists and local providers by dynamically displaying ongoing events and promotions.
Admin Dashboard: Centralize the management of user accounts, supplier data, and platform advertisements.

Core Tech Stack
----------------
Mobile Client: Flutter (Dart), flutter_map, flutter_map_tile_caching (FMTC), Provider state management.
Backend System: ASP.NET Core Web API (C#), Entity Framework Core.
Database: Microsoft SQL Server.
Mapping & GIS Data: OpenStreetMap (OSM) data, Foursquare API.
System Architecture
The project implements a robust Client-Server model integrated with an N-Tier (Layered) Architecture. This design strictly enforces the separation of concerns across the Presentation, Business Logic, and Data Access layers.
___________________________________________________________________________________________________________________________________________________________________
ADVANCED ALGORITHMIC IMPLEMENTATIONS
------------------------------------
To solve the unique challenges of a highly offline-capable travel application, the following algorithms and optimization techniques were engineered:
1. Intelligent Map Tile Caching Strategy
To ensure smooth offline functionality, the app goes beyond basic image downloading by utilizing advanced memory management techniques:
XYZ Tiling Model: Maps are partitioned into granular 256x256 pixel tiles. The algorithm mathematically determines the exact image files required based on geospatial coordinates (Lat/Lng) and the current Zoom Level.
LRU (Least Recently Used) Cache Eviction: Applied to the automated browsing cache. When the storage threshold is reached (e.g., 5,000 tiles), the LRU algorithm automatically identifies and purges the least accessed map tiles to free up space for new data.
Sea-Tile Filtering Heuristics: Leverages FMTC algorithms to detect tiles consisting solely of ocean water (analyzing image hashes or headers). The system skips downloading these redundant tiles, drastically reducing storage consumption.
2. Spatial Querying & Geolocation Optimization
Engineered to efficiently load advertisements and POIs (Points of Interest) strictly within the user's viewport (_loadAdsInView):
Bounding Box Querying: Instead of scanning the entire database, the system executes Bounding Box queries. As the user pans the map, the Client transmits four coordinate boundaries (North, South, East, West). The Server securely filters and returns only the data points $P(lat, lon)$ that fall within this exact viewport.
Great-Circle Distance Calculation: Utilizes geospatial formulas (such as the Haversine formula) to calculate the exact straight-line distance between the user's current GPS location and nearby destinations, driving the "Nearest to Me" sorting logic.
3. Security & Data Encryption
Cryptographic Password Hashing: User credentials are strictly protected. The backend implements the PBKDF2 algorithm (via ASP.NET Core Identity) with randomized salting to securely hash passwords prior to SQL Server storage.
Secure Authentication Flow: Implemented a stateless authentication system using JWT, ensuring secure user login, registration, and role-based access control across all API endpoints.
Hardware-Backed Keystore: For the in-app document "Safe" feature, the user's access PIN is secured using hardware-level encryption (Android Keystore / iOS Keychain) via the flutter_secure_storage library. This ensures PINs remain uncompromised even if the application's local data files are extracted.
5. Context-Aware Hybrid Recommendation Engine
The platform utilizes a sophisticated recommendation model combining Collaborative Filtering (analyzing user-item interactions) with Geo-spatial Filtering (filtering by physical proximity).
Cold-Start Fallback Mechanism: The system intelligently handles the "Cold-Start" problem. If a new user lacks historical behavioral data, or if GPS is unavailable, the engine seamlessly falls back to a Popularity-Based algorithm, dynamically rendering a "Top Rated" list based on the highest average ratings and review volumes.

_______________________________________________________________________________________________________________________________________________________________
Intelligent Hybrid Search Workflow
-----------------------------------
To ensure high data availability and accuracy while minimizing API costs, the location search functionality implements a multi-tier, fallback-driven architecture. The execution flow operates as follows:
1. Internal Database Query (SQL Server)
The system first queries the internal relational database to retrieve places created by local suppliers or previously saved data. This ensures ultra-low latency for partner locations.
2. Primary External Search (Foursquare API)
Simultaneously, the system queries the Foursquare API. Foursquare is prioritized as the primary external provider due to its rich, highly curated Point of Interest (POI) data, including high-quality images and accurate categorization.
3. Fallback Mechanism (OpenStreetMap)
To handle edge cases—such as remote backpacker trails or rural areas where commercial POI data might be sparse—the system evaluates the Foursquare response. If and only if Foursquare returns exactly 0 results, the system triggers a fallback query to the OpenStreetMap (Overpass) API to guarantee data availability.

Flow data chart
---------------
1. Search Internal (SQL) Flag display priority
2. Search Foursquare 
3. If Foursquare = 0
      ↓
   Search OSM
4. Merge
5. Deduplicate base on distance (<20m)
4. Data Aggregation (Merge)
Results from the Internal Database, Foursquare, and (conditionally) OSM are parsed into a standardized MapPlace object model and merged into a single, unified dataset.
5. Spatial Deduplication  
Because data originates from multiple independent sources, overlapping locations are inevitable. The system applies a geospatial deduplication algorithm. It calculates the Great-Circle distance between coordinates; if two data points are located within a 20-meter radius ($d < 20m$) of each other, they are flagged as duplicates and merged to provide a clean, clutter-free user interface.
