-- Migrate the existing OrderRating table in place. No row is dropped and no
-- parallel table is created. Legacy columns map directly:
--   score     -> stars       (1-5)
--   clientId  -> raterId     (the client is a rater)
--   captainId -> rateeId     (the captain is the ratee)
ALTER TABLE "OrderRating" RENAME COLUMN "score" TO "stars";
ALTER TABLE "OrderRating" RENAME COLUMN "clientId" TO "raterId";
ALTER TABLE "OrderRating" RENAME COLUMN "captainId" TO "rateeId";

-- The old table allowed only one rating per order. Both the client and the
-- captain may rate now, so the unique key becomes (orderId, raterId).
DROP INDEX IF EXISTS "OrderRating_orderId_key";
CREATE UNIQUE INDEX IF NOT EXISTS "OrderRating_orderId_raterId_key"
  ON "OrderRating"("orderId", "raterId");

-- Keep the existing captain lookup index aligned with the renamed column.
ALTER INDEX IF EXISTS "OrderRating_captainId_createdAt_idx"
  RENAME TO "OrderRating_rateeId_createdAt_idx";

-- Legacy rows predate the profile-average update. Recompute each captain's
-- average from the preserved rows so CaptainProfile.rating is not left at 0.
UPDATE "CaptainProfile" AS cp
SET "rating" = legacy."average"
FROM (
  SELECT "rateeId", AVG("stars")::double precision AS "average"
  FROM "OrderRating"
  GROUP BY "rateeId"
) AS legacy
WHERE cp."userId" = legacy."rateeId";
