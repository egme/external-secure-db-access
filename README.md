# Secure External Database Link With Data Labeling

This is excerpt from the work I made few years ago to achieve a few goals on a project:
- make micro-service local data available in an external analytics database via [FDW](https://www.postgresql.org/docs/current/postgres-fdw.html)
- restrict access to PII and secrets (access tokens, etc) with granular ACLs based on Postgres native authorization mechanisms

### Pre-conditions

The code base itself is an ordinary Ruby/Rails application, running as an API-only backend micro-service in a cloud. This particular service domain area is users and their identities. However, there are other micro-services and DBs, holding and managing business-specific data.

The need arose to have some general analytics view that aggregates data and relations across several DBs. At the same time strict data privacy requirements should have been met.

### Solution

Options like ETL, data lakes, event-sourcing, etc. back then were rejected and team decided to implement the simplest possible solution:
- dashboards connected to single `analytics` database, which resides in an isolated VPC
- each of the micro-services is responsible for exposing it's own data to the `analytics` DB
  - cross-VPC access is configured via [VPC peering](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html) in Terraform
  - each service is provided with privileged access to `analytics` DB and on each migration re-establishes FDW link between databases
- three sensitivity [labels](app/lib/database/data_labeling_config.rb#L3) are defined for all data managed by service:
  - `normal` - non-PII and non-secret data only, generally available for all staff
  - `pii` - personally identifyable information
  - `secret` - access tokens, passwords, recovery keys, etc
- three PG user [roles](app/lib/database/roles_config.rb#L7) definced with different data access levels
  - `service` - full access to data the service is responsible for, provided to service workloads only
  - `looker` - can see only general data fields marked as `normal`
  - `spy` - can see PII, but not secrets. Only a few people from compliance team should have this level of access
- each field of the service database should be explicitly marked with one of the labels
- foreign access from `analytics` DB to service data is limited with `looker` role
- to simplify analytics representation of own data service may define custom views
  - data in defined views should also respect labeling and prevent exposing sensitive fields externally

The only dependencies for this solution are:
- External `analytics` database privileged access provided via [ANALYTICS_DSN](app/lib/database/analytics.rb#L72) ENV variable. VPC peering config is out of scope of this example and is purely a Terraform magic.
- Pre-configured additional [looker](app/lib/database/analytics.rb#L43) role in micro-service's Postgres DB, managed via Terraform again

The rest is based on explicit labeling of data columns (see [DatalabelingConfig::LABELED_COLUMNS](app/lib/database/data_labeling_config.rb) and auto-discovery.

Since each service release is driven by CI/CD pipeline and migration step is required to launch new version of service - on each release, after database migration, all FDW and analytics views configuration and data labeling is being re-established from scratch.

### Goals achieved

1. Declarative [definition](app/lib/database/data_labeling_config.rb#L3) of sensitivity labels per each DB column
2. Declarative [definition](app/lib/database/views.rb#L5) and [version control](app/lib/database/views.rb#L6) of analytics views 
4. [Auto-discovery](app/lib/database/data_labeling_config.rb#L64) applies sensitivity labels to derived views based on the original tables/columns
2. Full labeling coverage of data is [enforced](test/lib/database/data_labeling_config_test.rb) with unit tests
3. Full [automation](lib/tasks/db.rake) of complex setup
5. Multi-level security and data protection

### Pros and cons

Upon implementing this solution it worked pretty well for our purposes. 
- The data was accessible at analytics dashboards/app immediately
- Data structures were clear enough for business staff to experiment with own queries
- Resulting solution proved to be very robust and secure

However, because of the FDW nature, we faced an issue when not optimized analytics queries, running against production micro-service databases over FDW were affecting the performance. Long-term solution to this might have been
- either linking `analytics` DB to read-only replicas of production data
- or implementing ETL / event-sourcing / data streaming of data to an analytics storage

Another drawback of this approach is a short period of data missing in analytics DB during service rollout, which was acceptable back then.
