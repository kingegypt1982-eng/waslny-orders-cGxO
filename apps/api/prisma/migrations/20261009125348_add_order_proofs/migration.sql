-- CreateEnum
CREATE TYPE "ProofType" AS ENUM ('PICKUP', 'DELIVERY');

-- CreateTable
CREATE TABLE "OrderProof" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "type" "ProofType" NOT NULL,
    "photoPath" TEXT,
    "capturedById" TEXT NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OrderProof_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "OrderProof_orderId_idx" ON "OrderProof"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "OrderProof_orderId_type_key" ON "OrderProof"("orderId", "type");

-- AddForeignKey
ALTER TABLE "OrderProof" ADD CONSTRAINT "OrderProof_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
