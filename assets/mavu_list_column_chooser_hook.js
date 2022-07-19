import Sortable from 'sortablejs';

const defineComponent = () => {
    Alpine.data('mavu_list_column_chooser_component', () => ({
        init() {
            this.setupSortable()
        },
        setupSortable() {
            console.log('#log 3433 setup sortable');
            Sortable.create(this.$refs.items, {
                handle: '.drag-handle',
                animation: 150,
                onUpdate: () => this.syncSortOrder()
            });
        },
        syncSortOrder() {
            let new_order_str = [...this.$refs.items.children]
                .map(item => {
                    let hiddenInput = item.querySelector('input[name$="[name]"]')
                    return hiddenInput ? hiddenInput.value : null
                })
                .filter( item => item!==null )
                .join(',');

            let orderInput = this.$el.querySelector('input[name$="[col_order]"]');
            orderInput.value=new_order_str;

        },
    }));
};
document.addEventListener('alpine:init', defineComponent);


window.addEventListener('phx:update_param_in_url', (e) => {
    const url = new URL(document.location);
    url.searchParams.set(e.detail.name, e.detail.value);
    window.history.pushState({}, '', url);
  });




const MavuListColumnChooserHook = {};
export default MavuListColumnChooserHook;
