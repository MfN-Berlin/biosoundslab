<script setup lang="ts">
import type { ThresholdItem } from "~/composables/api/thresholds";
import { useThresholdsPaginated, useThresholdUpdate } from "~/composables/api/thresholds";
import * as XLSX from 'xlsx';

// Set page layout to full-width for better table display
definePageMeta({ layout: "full-width" });

/**
 * Pagination options for the data table footer
 * Allows users to choose how many records to display per page
 */
const paginationOptions = [
  { value: 10, title: '10' },
  { value: 25, title: '25' },
  { value: 50, title: '50' },
  { value: 100, title: '100' },
];

/**
 * Get runtime configuration (may be used for API endpoints)
 */
const config = useRuntimeConfig();

/**
 * Utility function to access nested object properties
 * Handles dot-notation paths like "label.name" to get nested values
 *
 * @param {object} obj - The object to traverse
 * @param {string} key - Dot-notation path to the desired property
 * @returns {any} The value at the specified path, or undefined if not found
 *
 * @example
 * getNested({label: {name: "Test Label"}}, "label.name") // Returns "Test Label"
 */
function getNested(obj: any, key: string) {
  return key.split('.').reduce((o, k) => (o ? o[k] : undefined), obj);
}

// Type for pivoted threshold data - one row per label/model combination
interface PivotedThresholdRow {
  id: string; // composite key: model_id_label_id
  label: { id: string; name: string };
  model: { id: string; name: string };
  label_id: string;
  model_id: string;
  threshold_default: string | null;
  threshold_experimental: string | null;
  threshold_preliminary: string | null;
  threshold_final: string | null;
  threshold_ids: {
    default?: string;
    experimental?: string;
    preliminary?: string;
    final?: string;
  };
  set_at_default?: string;
  set_at_experimental?: string;
  set_at_preliminary?: string;
  set_at_final?: string;
}

// Reactive pivoted data
const pivotedItems = ref<PivotedThresholdRow[]>([]);
const pivotedLoading = ref<boolean>(true);
const pivotedTotalItems = ref<number>(0);
const pivotedPage = ref<number>(1);
const pivotedItemsPerPage = ref<number>(10);
const pivotedSortBy = ref<{ key: string; order: 'asc' | 'desc' }[]>([{ key: 'label.name', order: 'asc' }]);

/**
 * Fetch all thresholds and pivot them so each row represents a label/model combination
 * with the latest threshold value for each type
 */
async function fetchAndPivotThresholds(): Promise<PivotedThresholdRow[]> {
  const config = useRuntimeConfig();
  
  const result = await $fetch(config.public.GQL_HOST, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: {
      query: `
        query getAllThresholds {
          thresholds {
            id
            label_id
            model_id
            threshold
            threshold_type
            set_at
            label {
              id
              name
            }
            model {
              id
              name
            }
          }
        }
      `,
    },
  });

  const allThresholds: ThresholdItem[] = result.data?.thresholds || [];
  
  // Group by model_id + label_id
  const grouped = new Map<string, ThresholdItem[]>();
  allThresholds.forEach((item) => {
    const key = `${item.model_id}_${item.label_id}`;
    if (!grouped.has(key)) {
      grouped.set(key, []);
    }
    grouped.get(key)!.push(item);
  });
  
  // For each group, find the latest threshold for each type
  const pivotedRows: PivotedThresholdRow[] = [];
  grouped.forEach((items, key) => {
    const row: PivotedThresholdRow = {
      id: key,
      label: items[0].label || { id: '', name: '' },
      model: items[0].model || { id: '', name: '' },
      label_id: items[0].label_id,
      model_id: items[0].model_id,
      threshold_default: null,
      threshold_experimental: null,
      threshold_preliminary: null,
      threshold_final: null,
      threshold_ids: {},
    };
    
    // Find latest for each type
    const types = ['default', 'experimental', 'preliminary', 'final'] as const;
    types.forEach(type => {
      const typeItems = items.filter(item => item.threshold_type === type);
      if (typeItems.length > 0) {
        // Find the latest by set_at
        const latest = typeItems.reduce((prev, current) => {
          return new Date(current.set_at) > new Date(prev.set_at) ? current : prev;
        });
        row[`threshold_${type}`] = String(latest.threshold);
        row.threshold_ids[type] = latest.id;
        row[`set_at_${type}`] = latest.set_at;
      }
    });
    
    pivotedRows.push(row);
  });
  
  // Sort by label name ascending
  pivotedRows.sort((a, b) => {
    const aLabel = a.label?.name || '';
    const bLabel = b.label?.name || '';
    return aLabel.localeCompare(bLabel);
  });
  
  return pivotedRows;
}

/**
 * Load pivoted data - fetches all data once and lets the table handle pagination client-side
 */
async function loadPivotedData() {
  pivotedLoading.value = true;
  try {
    const allData = await fetchAndPivotThresholds();
    pivotedItems.value = allData;
    pivotedTotalItems.value = allData.length;
  } catch (error) {
    console.error('Error loading pivoted thresholds:', error);
  } finally {
    pivotedLoading.value = false;
  }
}

// Initial load
loadPivotedData();

const headers = [
  {
    title: "Label",
    key: "label.name",
    align: "start",
    sortable: true,
    search: { operator: "_like", type: "text" }
  },
  {
    title: "Model",
    key: "model.name",
    align: "start",
    sortable: true,
    search: { operator: "_like", type: "text" }
  },
  {
    title: "Default",
    key: "threshold_default",
    align: "end",
    sortable: true,
    search: false
  },
  {
    title: "Experimental",
    key: "threshold_experimental",
    align: "end",
    sortable: true,
    search: false
  },
  {
    title: "Preliminary",
    key: "threshold_preliminary",
    align: "end",
    sortable: true,
    search: false
  },
  {
    title: "Final",
    key: "threshold_final",
    align: "end",
    sortable: true,
    search: false
  },
  {
    title: "Actions",
    key: "actions",
    align: "center",
    sortable: false,
    search: false
  }
] as const;

// Get the update mutation
const { mutate: updateThreshold, isPending: isUpdating } = useThresholdUpdate();

// Dialog state for edit popup
const editDialog = ref(false);
const editingRow = ref<PivotedThresholdRow | null>(null);
const editingValues = ref<{
  default: number | null;
  experimental: number | null;
  preliminary: number | null;
  final: number | null;
}>({
  default: null,
  experimental: null,
  preliminary: null,
  final: null
});

// State for Final threshold lock
const finalLocked = ref(true);

// Dialog for unlock warning
const unlockWarningDialog = ref(false);

// Local loading state for save
const saving = ref(false);

// Scroller configuration for number inputs
const scrollerConfig = {
  min: 0,
  max: 1,
  step: 0.01
};

// Open edit dialog
const openEditDialog = (row: PivotedThresholdRow) => {
  editingRow.value = row;
  editingValues.value = {
    default: row.threshold_default !== null && row.threshold_default !== '-' ? parseFloat(row.threshold_default) : null,
    experimental: row.threshold_experimental !== null && row.threshold_experimental !== '-' ? parseFloat(row.threshold_experimental) : null,
    preliminary: row.threshold_preliminary !== null && row.threshold_preliminary !== '-' ? parseFloat(row.threshold_preliminary) : null,
    final: row.threshold_final !== null && row.threshold_final !== '-' ? parseFloat(row.threshold_final) : null
  };
  finalLocked.value = true; // Reset lock state when opening dialog
  editDialog.value = true;
};

// Show unlock warning dialog
const showUnlockWarning = () => {
  unlockWarningDialog.value = true;
};

// Unlock the final input
const unlockFinalInput = () => {
  finalLocked.value = false;
  unlockWarningDialog.value = false;
};

// Cancel unlock
const cancelUnlock = () => {
  unlockWarningDialog.value = false;
};

// Helper function to update threshold value via direct GraphQL mutation
async function updateThresholdValue(thresholdId: string, newValue: number): Promise<void> {
  const config = useRuntimeConfig();
  
  await $fetch(config.public.GQL_HOST, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: {
      query: `
        mutation updateThreshold($id: Int!, $threshold: Float!) {
          update_thresholds_by_pk(
            pk_columns: {id: $id}
            _set: {threshold: $threshold, set_at: "now()"}
          ) {
            id
            threshold
            set_at
          }
        }
      `,
      variables: {
        id: parseInt(thresholdId),
        threshold: newValue
      }
    },
  });
}

// Save edited values
const saveEditedValues = async () => {
  saving.value = true;
  try {
    if (!editingRow.value) return;
    
    const row = editingRow.value;
    const types = ['default', 'experimental', 'preliminary', 'final'] as const;
    
    // Update each threshold type that has a value
    for (const type of types) {
      const thresholdId = row.threshold_ids[type];
      const newValue = editingValues.value[type];
      
      // Only update if there's an existing threshold ID and a new value
      if (thresholdId && newValue !== null) {
        try {
          await updateThresholdValue(thresholdId, newValue);
        } catch (error) {
          console.error(`Error updating ${type} threshold:`, error);
          // Continue with other updates even if one fails
        }
      }
    }
    
    // Reload data and close dialog
    editDialog.value = false;
    editingRow.value = null;
    await loadPivotedData();
  } finally {
    saving.value = false;
  }
};

// Cancel edit
const cancelEdit = () => {
  editDialog.value = false;
  editingRow.value = null;
};



/**
 * Helper function to get pivoted data for exports
 * Returns all pivoted threshold rows
 */
async function getPivotedDataForExport(): Promise<PivotedThresholdRow[]> {
  // If we already have pivoted data loaded, use it
  if (pivotedItems.value.length > 0) {
    return pivotedItems.value;
  }
  // Otherwise fetch fresh
  return await fetchAndPivotThresholds();
}

// Function to export thresholds as CSV
const exportToCSV = async () => {
  try {
    const pivotedData = await getPivotedDataForExport();
    
    // Create CSV content with new column structure
    const csvHeaders = ['Label', 'Model', 'Default', 'Experimental', 'Preliminary', 'Final'];
    const csvRows = [];
    
    // Add header row
    csvRows.push(csvHeaders.join(','));
    
    // Add data rows
    pivotedData.forEach((item) => {
      const row = [
        `"${item.label?.name?.replace(/"/g, '""') || ''}"`,
        `"${item.model?.name?.replace(/"/g, '""') || ''}"`,
        item.threshold_default !== null && item.threshold_default !== '-' ? item.threshold_default : '-',
        item.threshold_experimental !== null && item.threshold_experimental !== '-' ? item.threshold_experimental : '-',
        item.threshold_preliminary !== null && item.threshold_preliminary !== '-' ? item.threshold_preliminary : '-',
        item.threshold_final !== null && item.threshold_final !== '-' ? item.threshold_final : '-',
      ];
      csvRows.push(row.join(','));
    });
    
    const csvContent = csvRows.join('\n');
    
    // Create and download the CSV file
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'thresholds.csv';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    
  } catch (error) {
    console.error("Error exporting to CSV:", error);
    alert("Failed to export thresholds as CSV");
  }
};

// Function to export thresholds as Excel
const exportToExcel = async () => {
  try {
    const pivotedData = await getPivotedDataForExport();
    
    // Create workbook
    const workbook = XLSX.utils.book_new();
    
    // Build complete array of arrays (headers + all data rows) with new column structure
    const aoa = [];
    aoa.push(['Label', 'Model', 'Default', 'Experimental', 'Preliminary', 'Final']);
    pivotedData.forEach((item) => {
      aoa.push([
        item.label?.name || '',
        item.model?.name || '',
        item.threshold_default !== null && item.threshold_default !== '-' ? item.threshold_default : '-',
        item.threshold_experimental !== null && item.threshold_experimental !== '-' ? item.threshold_experimental : '-',
        item.threshold_preliminary !== null && item.threshold_preliminary !== '-' ? item.threshold_preliminary : '-',
        item.threshold_final !== null && item.threshold_final !== '-' ? item.threshold_final : '-',
      ]);
    });
    
    // Create worksheet from the complete array
    const worksheet = XLSX.utils.aoa_to_sheet(aoa);
    
    // Add worksheet to workbook
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Thresholds');
    
    // Generate Excel file and download
    const excelBuffer = XLSX.write(workbook, { type: 'array', bookType: 'xlsx', ProBook: false });
    const blob = new Blob([excelBuffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'thresholds.xlsx';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    
  } catch (error) {
    console.error("Error exporting to Excel:", error);
    alert("Failed to export thresholds as Excel");
  }
};
</script>

<template>
  <v-container fluid>
    <div class="position-relative">
      <v-data-table
        v-model:items-per-page="pivotedItemsPerPage"
        v-model:page="pivotedPage"
        v-model:sort-by="pivotedSortBy"
        :headers="headers"
        :items="pivotedItems"
        :items-length="pivotedTotalItems"
        :loading="pivotedLoading"
        item-value="id"
        :items-per-page-options="paginationOptions"
        >
      <!--
        Table Row Template
        Custom template for each data row with pivoted threshold data
      -->
      <template #item="{ item }">
        <tr :style="{
          backgroundColor: item.threshold_final !== null && item.threshold_final !== '-' ? 'rgb(200, 230, 201)' :
                           item.threshold_preliminary !== null && item.threshold_preliminary !== '-' ? 'rgb(255, 249, 196)' :
                           item.threshold_experimental !== null && item.threshold_experimental !== '-' ? 'rgb(255, 230, 178)' : ''
        }">
          <td v-for="header in headers" :key="header.key" :style="{ textAlign: header.align === 'end' ? 'right' : header.align === 'center' ? 'center' : 'left' }">
            <template v-if="header.key !== 'actions'">
              <template v-if="header.key.startsWith('threshold_')">
                <span :style="{ color: header.key === 'threshold_default' ? '#999999' : 'inherit' }">
                  {{ item[header.key] !== null ? item[header.key] : '-' }}
                </span>
              </template>
              <template v-else>
                <span v-if="header.key === 'label.name'" style="font-style: italic;">
                  {{ getNested(item, header.key) }}
                </span>
                <span v-else>
                  {{ getNested(item, header.key) }}
                </span>
              </template>
            </template>
            <template v-else>
              <!-- EDIT button - opens popup with sliders for all 4 threshold types -->
              <v-btn
                size="small"
                color="primary"
                variant="outlined"
                @click.stop="openEditDialog(item)"
              >
                EDIT
              </v-btn>
            </template>
          </td>
        </tr>
      </template>
      </v-data-table>

      <!-- Download Buttons - positioned at bottom left, same height as paginator -->
      <div class="position-absolute bottom-0 left-0 d-flex">
        <v-btn 
          color="primary"
          variant="outlined"
          prepend-icon="mdi-download"
          @click.stop="exportToCSV"
          :loading="pivotedLoading"
          class="mr-2"
        >
          Download as CSV
        </v-btn>
        <v-btn 
          color="primary"
          variant="outlined"
          prepend-icon="mdi-file-excel"
          @click.stop="exportToExcel"
          :loading="pivotedLoading"
        >
          Download as Excel
        </v-btn>
      </div>
    </div>

    <!-- EDIT Dialog with scrollers for all 4 threshold types -->
    <v-dialog v-model="editDialog" max-width="600">
      <v-card>
        <v-card-title class="headline">Edit Thresholds</v-card-title>
        <v-card-text>
          <v-row>
            <v-col cols="12" sm="6">
              <v-label>Default</v-label>
              <v-text-field
                v-model="editingValues.default"
                type="number"
                :min="scrollerConfig.min"
                :max="scrollerConfig.max"
                :step="scrollerConfig.step"
                density="compact"
                hide-details
                disabled
                class="mt-1"
              ></v-text-field>
            </v-col>
            <v-col cols="12" sm="6">
              <v-label>Experimental</v-label>
              <v-text-field
                v-model="editingValues.experimental"
                type="number"
                :min="scrollerConfig.min"
                :max="scrollerConfig.max"
                :step="scrollerConfig.step"
                density="compact"
                hide-details
                class="mt-1"
              ></v-text-field>
            </v-col>
          </v-row>
          <v-row class="mt-4">
            <v-col cols="12" sm="6">
              <v-label>Preliminary</v-label>
              <v-text-field
                v-model="editingValues.preliminary"
                type="number"
                :min="scrollerConfig.min"
                :max="scrollerConfig.max"
                :step="scrollerConfig.step"
                density="compact"
                hide-details
                class="mt-1"
              ></v-text-field>
            </v-col>
            <v-col cols="12" sm="6">
              <div class="d-flex align-center">
                <v-label>Final</v-label>
                <v-btn
                  icon
                  size="x-small"
                  variant="text"
                  @click="showUnlockWarning"
                  class="ml-2"
                  :title="finalLocked ? 'Click to unlock' : 'Click to lock'"
                >
                  <v-icon :color="finalLocked ? 'grey' : 'primary'">
                    {{ finalLocked ? 'mdi-lock' : 'mdi-lock-open' }}
                  </v-icon>
                </v-btn>
              </div>
              <v-text-field
                v-model="editingValues.final"
                type="number"
                :min="scrollerConfig.min"
                :max="scrollerConfig.max"
                :step="scrollerConfig.step"
                density="compact"
                hide-details
                :disabled="finalLocked"
                class="mt-1"
              ></v-text-field>
            </v-col>
          </v-row>
        </v-card-text>
        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn color="grey" variant="text" @click="cancelEdit" :disabled="saving">
            Cancel
          </v-btn>
          <v-btn color="primary" variant="text" @click="saveEditedValues" :loading="saving">
            Save
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Warning Dialog for unlocking Final threshold -->
    <v-dialog v-model="unlockWarningDialog" max-width="500">
      <v-card>
        <v-card-title class="headline">Warning</v-card-title>
        <v-card-text>
          It is recommended to make changes only to the experimental or preliminary threshold, and to change the final threshold only based on new insights.
        </v-card-text>
        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn color="grey" variant="text" @click="cancelUnlock">
            Cancel
          </v-btn>
          <v-btn color="primary" variant="text" @click="unlockFinalInput">
            I understand, unlock the input
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>


  </v-container>

</template>