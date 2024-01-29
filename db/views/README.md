This directory contains definitions of views build on top of tables versioned via ActiveRecord.

Each file should be named `XX`.`SCHEMA`.`NAME`.sql, where:

- `XX`: ordering group number. In case when one view references another the first one should belong to an ordering group with lower number.
- `SCHEMA`: DB schema which the view belongs to.
- `NAME`: name of the view.

The file body should contain plain SQL request of the form `SELECT x, y, z FROM schema.table`, or a more complex one of the kind.

Views defined here are re-created automatically on each migration.
