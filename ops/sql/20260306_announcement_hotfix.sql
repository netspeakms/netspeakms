-- Idempotent schema hotfix for Announcement fields used by dashboard/message queries.
-- This protects startup after restore/redeploy when historical DBs are missing columns.
DO $$
BEGIN
    IF to_regclass('"Announcement"') IS NULL THEN
        RAISE NOTICE 'Skipping announcement hotfix because table "Announcement" does not exist.';
        RETURN;
    END IF;

    EXECUTE 'ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(6)';
    EXECUTE 'ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "senderId" TEXT';

    IF to_regclass('"Teacher"') IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'announcement_senderid_fkey'
        ) THEN
            EXECUTE
                'ALTER TABLE "Announcement" ' ||
                'ADD CONSTRAINT announcement_senderid_fkey ' ||
                'FOREIGN KEY ("senderId") REFERENCES "Teacher"("id") ' ||
                'ON DELETE SET NULL ON UPDATE CASCADE';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'announcement_senderid_idx'
    ) THEN
        EXECUTE 'CREATE INDEX announcement_senderid_idx ON "Announcement" ("senderId")';
    END IF;
END $$;
