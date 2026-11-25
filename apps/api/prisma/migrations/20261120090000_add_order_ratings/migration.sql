-- Additive: one optional client rating per completed order.
CREATE TABLE IF NOT EXISTS "OrderRating" (
  "id" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "clientId" TEXT NOT NULL,
  "captainId" TEXT NOT NULL,
  "score" INTEGER NOT NULL,
  "comment" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "OrderRating_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "OrderRating_orderId_key" ON "OrderRating"("orderId");
CREATE INDEX IF NOT EXISTS "OrderRating_captainId_createdAt_idx" ON "OrderRating"("captainId", "createdAt");

ALTER TABLE "OrderRating" ADD CONSTRAINT "OrderRating_orderId_fkey"
  FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
